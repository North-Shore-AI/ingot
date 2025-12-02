defmodule IngotWeb.HealthControllerTest do
  use IngotWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 OK when all services are healthy", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json = json_response(conn, 200)
      assert json["status"] == "healthy"
      assert json["timestamp"]

      assert services = json["services"]
      assert services["endpoint"] == "ok"
      assert services["forge"] == "ok"
      assert services["anvil"] == "ok"
    end

    test "includes timestamp in ISO8601 format", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json = json_response(conn, 200)
      assert timestamp = json["timestamp"]

      # Verify it's a valid ISO8601 datetime string
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(timestamp)
    end

    test "health endpoint does not require authentication", %{conn: conn} do
      # Even without session/auth, health check should work
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200)
    end
  end
end
