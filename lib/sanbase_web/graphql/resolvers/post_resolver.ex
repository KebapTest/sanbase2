defmodule SanbaseWeb.Graphql.Resolvers.PostResolver do
  require Logger
  require Sanbase.Utils.Config, as: Config
  require Mockery.Macro

  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Tag
  alias Sanbase.Insight.{Post, Poll}
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Notifications
  alias SanbaseWeb.Graphql.Helpers.Utils

  def insights(%User{} = user, _args, _resolution) do
    posts = Post.user_insights(user.id)

    {:ok, posts}
  end

  def post(_root, %{id: post_id}, _resolution) do
    case Repo.get(Post, post_id) do
      nil -> {:error, "There is no post with id #{post_id}"}
      post -> {:ok, post}
    end
  end

  def all_insights(_root, %{tags: tags, page: page, page_size: page_size}, _context)
      when is_list(tags) do
    posts = Post.public_insights_by_tags(tags, page, page_size)

    {:ok, posts}
  end

  def all_insights(_root, %{page: page, page_size: page_size}, _resolution) do
    posts = Post.public_insights(page, page_size)

    {:ok, posts}
  end

  def all_insights_for_user(_root, %{user_id: user_id}, _context) do
    posts = Post.user_public_insights(user_id)

    {:ok, posts}
  end

  def all_insights_user_voted_for(_root, %{user_id: user_id}, _context) do
    posts = Post.all_insights_user_voted_for(user_id)

    {:ok, posts}
  end

  def all_insights_by_tag(_root, %{tag: tag}, _context) do
    posts = Post.public_insights_by_tag(tag)

    {:ok, posts}
  end

  def related_projects(post, _, _) do
    tags = post.tags |> Enum.map(& &1.name)

    query =
      from(
        p in Project,
        where: p.ticker in ^tags and not is_nil(p.coinmarketcap_id)
      )

    {:ok, Repo.all(query)}
  end

  def create_post(_root, post_args, %{
        context: %{auth: %{current_user: user}}
      }) do
    %Post{user_id: user.id, poll_id: Poll.find_or_insert_current_poll!().id}
    |> Post.create_changeset(post_args)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        {:ok, post}

      {:error, changeset} ->
        {
          :error,
          message: "Can't create post", details: Utils.error_details(changeset)
        }
    end
  end

  def update_post(_root, %{id: post_id} = post_args, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    draft_state = Post.draft()
    published_state = Post.published()

    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id, ready_state: ^draft_state} = post ->
        post
        |> Repo.preload([:tags, :images])
        |> Post.update_changeset(post_args)
        |> Repo.update()
        |> case do
          {:ok, post} ->
            {:ok, post}

          {:error, changeset} ->
            {
              :error,
              message: "Can't update post", details: Utils.error_details(changeset)
            }
        end

      %Post{user_id: another_user_id} when user_id != another_user_id ->
        {:error, "Cannot update not owned post: #{post_id}"}

      %Post{user_id: ^user_id, ready_state: ^published_state} ->
        {:error, "Cannot update published post: #{post_id}"}

      _post ->
        {:error, "Cannot update post with id: #{post_id}"}
    end
  end

  def delete_post(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    case Repo.get(Post, post_id) do
      %Post{user_id: ^user_id} = post ->
        # Delete the images from the S3/Local store.
        delete_post_images(post)

        # Note: When ecto changeset middleware is implemented return just `Repo.delete(post)`
        case Repo.delete(post) do
          {:ok, post} ->
            {:ok, post}

          {:error, changeset} ->
            {
              :error,
              message: "Can't delete post with id #{post_id}",
              details: Utils.error_details(changeset)
            }
        end

      _post ->
        {:error, "You don't own the post with id #{post_id}"}
    end
  end

  def all_tags(_root, _args, _context) do
    {:ok, Repo.all(Tag)}
  end

  def publish_insight(_root, %{id: post_id}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    Post.publish(post_id, user_id)
  end

  # Helper functions

  defp delete_post_images(%Post{} = post) do
    extract_image_url_from_post(post)
    |> Enum.map(&Sanbase.FileStore.delete/1)
  end

  defp extract_image_url_from_post(%Post{} = post) do
    post
    |> Repo.preload(:images)
    |> Map.get(:images, [])
    |> Enum.map(fn %{image_url: image_url} -> image_url end)
  end
end
