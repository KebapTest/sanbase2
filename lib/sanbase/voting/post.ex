defmodule Sanbase.Voting.Post do
  use Ecto.Schema
  import Ecto.Changeset
  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Auth.User

  schema "posts" do
    belongs_to(:poll, Poll)
    belongs_to(:user, User)
    has_many(:votes, Vote)

    field(:title, :string)
    field(:link, :string)
    field(:approved_at, Timex.Ecto.DateTime)

    timestamps()
  end

  def changeset(%Post{} = post, attrs \\ %{}) do
    post
    |> cast(attrs, [:title, :link])
    |> validate_required([:poll_id, :user_id, :title, :link])
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def admin_changeset(%Post{} = post, attrs \\ %{}) do
    post
    |> cast(attrs, [:poll_id, :title, :link, :approved_at])
    |> validate_required([:poll_id, :user_id, :title, :link])
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def approve_changeset(%Post{} = post) do
    post
    |> change(approved_at: Timex.now())
  end
end
