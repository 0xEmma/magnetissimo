defmodule Magnetissimo.Torrents.Torrent do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Magnetissimo.Torrents.Source
  alias Magnetissimo.Torrents.Category

  @primary_key {:id, :string, autogenerate: {Ecto.Nanoid, :autogenerate, []}}
  @foreign_key_type :string
  typed_schema "torrents" do
    field(:name, :string)
    field(:slug, :string)
    field(:published_at, :utc_datetime_usec)
    field(:description, :string)
    field(:canonical_url, :string)
    field(:magnet_url, :string)
    field(:magnet_hash, :string)
    field(:leechers, :integer)
    field(:seeders, :integer)
    field(:size_in_bytes, :integer)

    belongs_to(:category, Category)
    belongs_to(:source, Source)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(torrent, attrs) do
    torrent
    |> cast(attrs, [
      :name,
      :description,
      :canonical_url,
      :published_at,
      :leechers,
      :seeders,
      :size_in_bytes,
      :magnet_url,
      :magnet_hash,
      :category_id,
      :source_id
    ])
    |> validate_required([
      :name,
      :canonical_url,
      :published_at,
      :leechers,
      :seeders,
      :size_in_bytes,
      :magnet_url,
      :magnet_hash,
      :category_id,
      :source_id
    ])
    |> unique_constraint(:magnet_hash)
    |> validate_length(:magnet_hash, min: 40, max: 40)
    |> validate_format(:magnet_url, ~r/^(?!magnet:)/,
      message: "must not start with `magnet:` - we add that on the frontend."
    )
    |> put_slug()
  end

  def put_slug(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{name: name}} ->
        slug = Slug.slugify(name, separator: "-")

        changeset
        |> put_change(:slug, slug)

      _ ->
        changeset
    end
  end
end
