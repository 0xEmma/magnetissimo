defmodule Magnetissimo.Crawlers.Leetx do
  require Logger

  alias Magnetissimo.Torrents
  alias Magnetissimo.Utils

  @spec fast_search(binary()) :: :ok
  def fast_search(search_term) do
    source = Torrents.get_source_by_name!("1337x")

    1..1
    |> Enum.each(fn page ->
      search_term
      |> get_search_page_html(page)
      |> parse_table()
      |> List.flatten()
      |> Enum.chunk_every(2)
      |> Task.async_stream(
        fn torrent_urls ->
          torrent_urls
          |> Enum.each(fn torrent_url ->
            torrent_url
            |> get_page_html()
            |> parse_torrent_page(torrent_url, source)
            |> Torrents.create_torrent_for_source(source.name)
          end)
        end,
        ordered: false,
        timeout: :infinity
      )
      |> Stream.run()
    end)
  end

  def search(search_term) do
    source = Torrents.get_source_by_name!("1337x")

    page_count =
      search_term
      |> get_search_page_html()
      |> get_page_count()

    1..page_count
    |> Enum.each(fn page ->
      search_term
      |> get_search_page_html(page)
      |> parse_table()
      |> List.flatten()
      |> Enum.each(fn torrent_url ->
        torrent_url
        |> get_page_html()
        |> parse_torrent_page(torrent_url, source)
        |> Torrents.create_torrent_for_source(source.name)
      end)
    end)
  end

  @spec get_page_count(String.t()) :: integer()
  def get_page_count(search_page_html) do
    pages =
      search_page_html
      |> Floki.parse_document!()
      |> Floki.find(".pagination ul li")

    if Enum.any?(pages) do
      last_pagination_li =
        pages
        |> Enum.filter(fn page ->
          text =
            page
            |> Floki.find("a")
            |> Floki.text()

          text == "Last"
        end)

      href =
        last_pagination_li
        |> Floki.find("a")
        |> Floki.attribute("href")
        |> List.first()

      Regex.run(~r{/\d+/$}, href)
      |> List.first()
      |> String.replace("/", "")
      |> String.to_integer()
    else
      1
    end
  end

  def crawl_latest do
    Logger.info("[1337x] Crawling latest torrents.")

    category_pages =
      [
        "Anime",
        "Apps",
        "Documentaries",
        "Games",
        "Movies",
        "Music",
        "Other",
        "TV",
        "XXX"
      ]
      |> Enum.map(&"https://1337x.to/cat/#{&1}/1/")

    source = Torrents.get_source_by_name!("1337x")

    category_pages
    |> Enum.map(&get_page_html/1)
    |> Enum.map(&parse_table/1)
    |> List.flatten()
    |> Enum.each(fn torrent_url ->
      torrent_url
      |> get_page_html()
      |> parse_torrent_page(torrent_url, source)
      |> Torrents.create_torrent_for_source(source.name)
    end)
  end

  def parse_table(page_html) do
    page_html
    |> Floki.parse_document!()
    |> Floki.find("table a")
    |> Enum.filter(fn a ->
      a |> Floki.attribute("href") |> List.first() |> String.starts_with?("/torrent/")
    end)
    |> Enum.map(fn a ->
      "https://www.1337x.to" <> (a |> Floki.attribute("href") |> List.first())
    end)
  end

  def parse_torrent_page(torrent_page_html, canonical_url, source) do
    torrent_page_html =
      torrent_page_html
      |> Floki.parse_document!()

    name =
      torrent_page_html
      |> Floki.find("title")
      |> Floki.text()
      |> String.replace(" Torrent | 1337x", "")
      |> String.replace_leading("Download ", "")
      |> String.trim()

    leechers =
      torrent_page_html
      |> Floki.find("span.leeches")
      |> Floki.text()
      |> String.to_integer()

    seeders =
      torrent_page_html
      |> Floki.find("span.seeds")
      |> Floki.text()
      |> String.to_integer()

    magnet_url =
      torrent_page_html
      |> Floki.find(".box-info a")
      |> Enum.filter(fn a ->
        a |> Floki.attribute("href") |> List.first() |> String.starts_with?("magnet:")
      end)
      |> List.first()
      |> Floki.attribute("href")
      |> List.first()
      |> String.replace("magnet:", "")

    magnet_hash =
      torrent_page_html
      |> Floki.find(".infohash-box")
      |> Floki.text()
      |> String.replace("Infohash :", "")

    description =
      torrent_page_html
      |> Floki.find("div#description")
      |> Floki.raw_html()

    # The datetime string is in relative string format.
    # I couldn't find a good way to convert "2 hours ago" to a datetime.
    # Timex doesn't support this, and the only other library I found
    # doesn't support past relative time strings.
    # Figure this out later.
    # published_at =
    #   torrent_page_html
    #   |> Floki.find(".torrent-detail-page ul.list li")
    #   |> Enum.filter(fn li ->
    #     li |> Floki.text() |> String.starts_with?("Date uploaded")
    #   end)
    #   |> List.first()
    #   |> Floki.text()
    #   |> String.replace("Date uploaded", "")

    published_at = DateTime.utc_now()

    size_in_bytes =
      torrent_page_html
      |> Floki.find(".torrent-detail-page ul.list li")
      |> Enum.filter(fn li ->
        li |> Floki.text() |> String.starts_with?("Total size")
      end)
      |> List.first()
      |> Floki.text()
      |> String.replace("Total size", "")
      |> Utils.size_to_bytes()

    category =
      torrent_page_html
      |> Floki.find(".torrent-detail-page ul.list li")
      |> Enum.filter(fn li ->
        li |> Floki.text() |> String.starts_with?("Category")
      end)
      |> List.first()
      |> Floki.text()
      |> String.replace("Category", "")
      |> Torrents.get_category_by_name_or_alias!()

    %{
      canonical_url: canonical_url,
      leechers: leechers,
      magnet_url: magnet_url,
      magnet_hash: magnet_hash,
      name: name,
      description: description,
      published_at: published_at,
      seeders: seeders,
      size_in_bytes: size_in_bytes,
      category_id: category.id,
      source_id: source.id
    }
  end

  def get_page_html(url) do
    %{status_code: 200, body: body} = HTTPoison.get!(url)

    body
  end

  @spec get_search_page_html(binary(), integer()) :: binary()
  def get_search_page_html(search_term, page \\ 1) do
    Logger.info("[1337x] Fetching search results page.")

    search_term =
      search_term
      |> String.replace(" ", "+")

    %{status_code: 200, body: body} =
      "https://www.1337x.to/search/#{search_term}/#{page}/"
      |> HTTPoison.get!()

    body
  end
end
