require Logger

defmodule CloudOS.Messaging.AMQP.SubscriptionHandlerTest do
  use ExUnit.Case

  alias AMQP.Connection
  alias AMQP.Channel
  alias AMQP.Basic
  alias AMQP.Exchange
  alias AMQP.Queue

  alias CloudOS.Messaging.AMQP.SubscriptionHandler

  alias CloudOS.Messaging.Queue, as: MessagingQueue
  alias CloudOS.Messaging.AMQP.Exchange, as: MessagingExchange

  # =======================================
  # handle_call({:process_request}) tests

  test "handle_call({:process_request}) - process success" do
    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(payload, meta) ->
      :ok
    end

    payload = :erlang.term_to_binary("{}")

    state = %{
      channel: "channel", 
      exchange: queue.exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }
    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
    assert result == :ok
    assert returned_state == state
  end  

  test "handle_call({:process_request}) - requeue success" do
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :reject, fn _, _, opts -> 
      assert opts[:requeue] == true
      :ok 
    end)

    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(payload, meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    state = %{
      channel: "channel", 
      exchange: queue.exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }
    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
    assert result == :ok
    assert returned_state == state
  after
    :meck.unload(Basic)
  end

  test "handle_call({:process_request}) - requeue failure" do
    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: true
    }

    callback_handler = fn(payload, meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    try do
      state = %{
        channel: "channel", 
        exchange: queue.exchange, 
        queue: queue, 
        callback_handler: callback_handler
      }
      {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
      assert true == false
    rescue exception ->
      assert exception != nil
    end
  end  

  test "handle_call({:process_request}) - requeue disabled" do
    queue = %MessagingQueue{
      name: "test_queue", 
      requeue_on_error: false,
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(payload, meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    try do
      state = %{
        channel: "channel", 
        exchange: queue.exchange, 
        queue: queue, 
        callback_handler: callback_handler
      }
      {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
      assert true == false
    rescue exception ->
      assert exception != nil
    end
  end

  ## =============================
  # handle_call({:subscribe_sync}) tests   

  test "handle_call({:subscribe_sync}) - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn channel, exchange_name, type, opts -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn channel, queue_name, opts -> :ok end)
    :meck.expect(Queue, :bind, fn channel, queue_name, exchange_name, opts -> :ok end)
    :meck.expect(Queue, :subscribe, fn channel, queue_name, callback_handler -> :ok end)

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}

    callback_handler = fn(payload, meta) ->
      raise "bad news bears"
    end

    state = %{
      channel: "channel", 
      exchange: exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }

    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:subscribe_sync}, %{}, state)
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
  end      
end