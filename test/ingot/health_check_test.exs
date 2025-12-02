defmodule Ingot.HealthCheckTest do
  use ExUnit.Case, async: true

  alias Ingot.HealthCheck

  describe "status/0" do
    test "returns healthy when all services are healthy" do
      # Mock adapters are configured by default and always return :healthy
      assert :healthy = HealthCheck.status()
    end

    test "returns map with detailed service statuses" do
      result = HealthCheck.detailed_status()

      assert %{
               status: :healthy,
               services: services,
               timestamp: timestamp
             } = result

      assert %{
               endpoint: endpoint_status,
               forge: forge_status,
               anvil: anvil_status
             } = services

      # All services should be healthy with mock adapters
      assert endpoint_status == :ok
      assert forge_status == :ok
      assert anvil_status == :ok

      # Timestamp should be a DateTime
      assert %DateTime{} = timestamp
    end
  end

  describe "check_endpoint/0" do
    test "returns :ok when endpoint is running" do
      # Endpoint is running in test environment
      assert :ok = HealthCheck.check_endpoint()
    end
  end

  describe "check_forge/0" do
    test "returns :ok when Forge is healthy" do
      # Mock adapter returns {:ok, :healthy}
      assert :ok = HealthCheck.check_forge()
    end
  end

  describe "check_anvil/0" do
    test "returns :ok when Anvil is healthy" do
      # Mock adapter returns {:ok, :healthy}
      assert :ok = HealthCheck.check_anvil()
    end
  end
end
