defmodule CloudOS.Messaging.ConsumerTest do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options %CloudOS.Messaging.AMQP.ConnectionOptions{
		username: "username",
		password: "password",
		virtual_host: "vhost",
		host: "host"
	}
	use CloudOS.Messaging
end

defmodule CloudOS.Messaging.Consumer2Test do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	use CloudOS.Messaging

	@queue %Queue{name: "test_queue", exchange: %AMQPExchange{name: "aws:us-east-1b"}}

	def subscribe() do
		IO.puts("subscribe in TestConsumer2")
		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:cloudos_amqp, :username),
			password: Application.get_env(:cloudos_amqp, :password),
			virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
			host: Application.get_env(:cloudos_amqp, :host)
		}

		case subscribe(options, @queue, fn(payload, _meta) -> handle_msg(payload, _meta) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def send_message(payload) do
		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:cloudos_amqp, :username),
			password: Application.get_env(:cloudos_amqp, :password),
			virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
			host: Application.get_env(:cloudos_amqp, :host)
		}

		IO.puts("sending message:  #{inspect payload}")
		publish(options, @queue, payload)
	end	

	def handle_msg(payload, _meta) do
		try do
			IO.puts("TestConsumer2:  received message #{inspect payload}")
		rescue e in _ ->
			IO.puts("TestConsumer2:  Error when reviewing received message:  #{inspect e}")
		end		
	end	
end


defmodule CloudOS.MessagingTest do
  use ExUnit.Case

	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionPool
	alias CloudOS.Messaging.AMQP.ConnectionPools
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange 

  alias CloudOS.Messaging.ConsumerTest
  alias CloudOS.Messaging.Consumer2Test

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe attribute options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "subscribe attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == {:error, "bad news bears"}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "subscribe attribute options - invalid connection pool" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end 

   test "publish attribute options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "publish attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "publish attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end
end
