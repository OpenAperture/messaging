defmodule OpenAperture.Messaging.ConnectionOptionsResolverTestExternal do
  use ExUnit.Case
  @moduletag :external

  test "retrieve creds" do
    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(OpenAperture.ManagerAPI.get_api(), 1)
    IO.puts("options:  #{inspect options}")
  end
end