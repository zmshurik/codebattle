defmodule CodebattleWeb.GameController do
  use CodebattleWeb, :controller
  import CodebattleWeb.Gettext
  import PhoenixGon.Controller
  require Logger

  alias Codebattle.GameProcess.{Play, ActiveGames, FsmHelpers}
  alias Codebattle.Languages
  alias Codebattle.Bot.Playbook

  plug(CodebattleWeb.Plugs.RequireAuth when action in [:create, :join])

  action_fallback(CodebattleWeb.FallbackController)

  def create(conn, params) do
    type =
      case params["type"] do
        "withFriend" -> "private"
        "withRandomPlayer" -> "public"
        type -> type
      end

    game_params = %{
      level: params["level"],
      type: type,
      timeout_seconds: params["timeout_seconds"],
      user: conn.assigns.current_user
    }

    with {:ok, fsm} <- Play.create_game(game_params) do
      game_id = FsmHelpers.get_game_id(fsm)
      level = FsmHelpers.get_level(fsm)
      redirect(conn, to: game_path(conn, :show, game_id, level: level))
    end
  end

  def show(conn, %{"id" => id}) do
    case Play.get_fsm(id) do
      {:ok, fsm} ->
        conn = put_gon(conn, game_id: id)
        is_participant = ActiveGames.participant?(id, conn.assigns.current_user.id)

        case {fsm.state, is_participant} do
          {:waiting_opponent, false} ->
            render(conn, "join.html", %{fsm: fsm})

          _ ->
            render(conn, "show.html", %{fsm: fsm, layout_template: "full_width.html"})
        end

      {:error, _reason} ->
        case Play.get_game(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> put_view(CodebattleWeb.ErrorView)
            |> render("404.html", %{msg: gettext("Game not found")})

          game ->
            if Playbook.exists?(id) do
              langs = Languages.meta() |> Map.values()

              conn
              |> put_gon(is_record: true, game_id: id, langs: langs)
              |> render("show.html", %{layout_template: "full_width.html"})
            else
              render(conn, "game_result.html", %{game: game})
            end
        end
    end
  end

  def join(conn, %{"id" => id}) do
    case Play.join_game(id, conn.assigns.current_user) do
      {:ok, _fsm} ->
        conn
        |> redirect(to: game_path(conn, :show, id))

      {:error, reason} ->
        conn
        |> put_flash(:danger, reason)
        |> redirect(to: page_path(conn, :index))
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Play.cancel_game(id, conn.assigns.current_user) do
      redirect(conn, to: page_path(conn, :index))
    end
  end
end
