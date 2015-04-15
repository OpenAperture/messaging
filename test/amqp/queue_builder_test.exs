defmodule OpenAperture.Messaging.AMQP.QueueBuilderTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.ExchangeResolver

  alias OpenAperture.ManagerApi

  # =========================================
  # get_exchange tests

  test "build - success" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> %OpenAperture.Messaging.AMQP.Exchange{name: ""} end)

    queue = QueueBuilder.build(ManagerApi.get_api, "test_queue", "1")
    assert queue != nil
    assert queue.exchange != nil
  after
    :meck.unload(ExchangeResolver)
  end

  test "build - failure" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> nil end)

    queue = QueueBuilder.build(ManagerApi.get_api, "test_queue", "1")
    assert queue != nil
    assert queue.exchange == nil
  after
    :meck.unload(ExchangeResolver)    
  end

  test "build - success with options" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> %OpenAperture.Messaging.AMQP.Exchange{name: ""} end)

    queue = QueueBuilder.build(ManagerApi.get_api, "test_queue", "1", [durable: false])
    assert queue != nil
    assert queue.exchange != nil
    assert Keyword.get(queue.options, :durable) == false
  after
    :meck.unload(ExchangeResolver)
  end  
end