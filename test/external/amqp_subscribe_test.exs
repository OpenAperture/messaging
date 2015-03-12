require Logger

defmodule CloudOS.Messaging.AMQP.TestConsumerSub do

	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options %CloudOS.Messaging.AMQP.ConnectionOptions{
		username: Application.get_env(:cloudos_amqp, :username),
		password: Application.get_env(:cloudos_amqp, :password),
		virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
		host: Application.get_env(:cloudos_amqp, :host)
	}
	use CloudOS.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

	def subscribe() do
		IO.puts("subscribe")
		case subscribe(@queue, fn(payload, _meta) -> handle_msg(payload, _meta) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def send_message(payload) do
		IO.puts("sending message:  #{inspect payload}")
		publish(@queue, payload)
	end		

	def handle_msg(payload, _meta) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
		end		
	end	
end

defmodule CloudOS.Messaging.AMQP.TestConsumerSub2 do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options nil
	use CloudOS.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

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


defmodule CloudOS.Messaging.AMQP.SubscribeTest do
  use ExUnit.Case
  @moduletag :external

  alias CloudOS.Messaging.AMQP.TestConsumerSub
  alias CloudOS.Messaging.AMQP.TestConsumerSub2

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe" do
  	CloudOS.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerSub.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  

  test "subscribe2" do
  	CloudOS.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerSub2.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  
end
