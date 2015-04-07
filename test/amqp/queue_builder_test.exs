defmodule CloudOS.Messaging.AMQP.QueueBuilderTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias CloudOS.Messaging.AMQP.QueueBuilder
  alias CloudOS.Messaging.AMQP.ExchangeResolver

  alias CloudOS.ManagerAPI

  # =========================================
  # get_exchange tests

  test "build - success" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> %CloudOS.Messaging.AMQP.Exchange{name: ""} end)

    queue = QueueBuilder.build(ManagerAPI.get_api, "test_queue", "1")
    assert queue != nil
    assert queue.exchange != nil
  after
    :meck.unload(ExchangeResolver)
  end

  test "build - failure" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> nil end)

    queue = QueueBuilder.build(ManagerAPI.get_api, "test_queue", "1")
    assert queue != nil
    assert queue.exchange == nil
  after
    :meck.unload(ExchangeResolver)    
  end
end