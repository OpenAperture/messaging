defmodule CloudOS.Messaging.ConnectionOptionsResolverTestExternal do
  use ExUnit.Case
  @moduletag :external

  test "retrieve creds" do
    options = CloudOS.Messaging.ConnectionOptionsResolver.get_for_broker(CloudOS.ManagerAPI.get_api(), 1)
    IO.puts("options:  #{inspect options}")
  end
end