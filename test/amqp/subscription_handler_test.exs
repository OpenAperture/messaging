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

  ## =============================
  # deserialize tests   

  test "deserialize - success" do
    SubscriptionHandler.deserialize(:erlang.term_to_binary(%{})) == %{}
  end

  test "deserialize - nil" do
    SubscriptionHandler.deserialize(:erlang.term_to_binary(nil)) == nil
  end

  ## =============================
  # deserialize tests   

  test "serilalize - success" do
    SubscriptionHandler.serilalize(%{}) == :erlang.term_to_binary(%{})
  end

  test "serilalize - nil" do
    SubscriptionHandler.serilalize(nil) == :erlang.term_to_binary(nil)
  end

  ## =============================
  # process_async_request tests

  test "process_async_request - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn channel, exchange_name, type, opts -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn channel, queue_name, opts -> :ok end)
    :meck.expect(Queue, :bind, fn channel, queue_name, exchange_name, opts -> :ok end)
    :meck.expect(Queue, :subscribe, fn channel, queue_name, callback_handler -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _ -> :ok end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{recieved_message: false} end)
    callback_handler = fn(payload, meta, async_info) ->
      try do
        Agent.update(test_agent, fn _ -> %{recieved_message: true} end)
      rescue e ->
        IO.puts("An unexpected error occurred in test 'process_async_request - success':  #{inspect e}")
      end
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler = SubscriptionHandler.subscribe(%{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
      })

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    test_pid = spawn_link fn -> SubscriptionHandler.process_async_request(channel, callback_handler, subscription_handler) end
    send(test_pid, {:basic_deliver, payload, meta})
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:recieved_message] == true
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end  

  test "process_async_request - failure" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn channel, exchange_name, type, opts -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn channel, queue_name, opts -> :ok end)
    :meck.expect(Queue, :bind, fn channel, queue_name, exchange_name, opts -> :ok end)
    :meck.expect(Queue, :subscribe, fn channel, queue_name, callback_handler -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _ -> :ok end)
    :meck.expect(Basic, :reject, fn _, _, _ -> :ok end)

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{recieved_message: false} end)
    callback_handler = fn(payload, meta, async_info) ->
      raise "bad news bears"
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue"
    }

    subscription_handler = SubscriptionHandler.subscribe(%{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
      })

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    test_pid = spawn_link fn -> SubscriptionHandler.process_async_request(channel, callback_handler, subscription_handler) end
    send(test_pid, {:basic_deliver, payload, meta})
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:recieved_message] == false
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end    

  test "process_async_request - basic_cancel" do
    callback_handler = fn(payload, meta, async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.process_async_request("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end
    end
    send(test_pid, {:basic_cancel, %{no_wait: true}})
    :timer.sleep(100)
  end  

  test "process_async_request - basic_cancel_ok" do
    callback_handler = fn(payload, meta, async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.process_async_request("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end            
    end
    send(test_pid, {:basic_cancel_ok, %{no_wait: true}})
    :timer.sleep(100)
  end  

  ## =============================
  # start_async_handler tests

  test "start_async_handler - basic_consume_ok" do
    callback_handler = fn(payload, meta, async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      SubscriptionHandler.start_async_handler("channel", callback_handler, %{})            
    end
    send(test_pid, {:basic_consume_ok, %{consumer_tag: "#{UUID.uuid1()}"}})
    :timer.sleep(100)
  end   

  test "start_async_handler - other" do
    callback_handler = fn(payload, meta, async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.start_async_handler("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end            
    end
    send(test_pid, {:basic_consume_failed, %{}})
    :timer.sleep(100)
  end    
end