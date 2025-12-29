ExUnit.start()

# Start the endpoint for LiveView tests
{:ok, _} = Application.ensure_all_started(:ingot)
