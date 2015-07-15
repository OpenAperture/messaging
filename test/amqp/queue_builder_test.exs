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
    assert queue.binding_options[:routing_key] == queue.name
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
    assert queue.binding_options[:routing_key] == queue.name
    assert Keyword.get(queue.options, :durable) == false
  after
    :meck.unload(ExchangeResolver)
  end  

  test "build - success with routing_key" do
    :meck.new(ExchangeResolver, [:passthrough])
    :meck.expect(ExchangeResolver, :get, fn _,_ -> %OpenAperture.Messaging.AMQP.Exchange{name: ""} end)

    queue = QueueBuilder.build(ManagerApi.get_api, "test_queue", "1", [], [routing_key: "my_routing_key"])
    assert queue != nil
    assert queue.exchange != nil
    assert queue.binding_options[:routing_key] == "my_routing_key"
  after
    :meck.unload(ExchangeResolver)
  end  

  test "build_with_exchange - success" do
    queue = QueueBuilder.build_with_exchange("test_queue", %OpenAperture.Messaging.AMQP.Exchange{name: ""})
    assert queue != nil
    assert queue.exchange != nil
    assert queue.binding_options[:routing_key] == queue.name
  end

  test "build_with_exchange - success with options" do
    queue = QueueBuilder.build_with_exchange("test_queue", %OpenAperture.Messaging.AMQP.Exchange{name: ""}, [durable: false])
    assert queue != nil
    assert queue.exchange != nil
    assert queue.binding_options[:routing_key] == queue.name
    assert Keyword.get(queue.options, :durable) == false
  end  

  test "build_with_exchange - success with routing_key" do
    queue = QueueBuilder.build_with_exchange("test_queue", %OpenAperture.Messaging.AMQP.Exchange{name: ""}, [], [routing_key: "my_routing_key"])
    assert queue != nil
    assert queue.exchange != nil
    assert queue.binding_options[:routing_key] == "my_routing_key"
  end  
end