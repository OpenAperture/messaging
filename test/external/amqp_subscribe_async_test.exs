require Logger

defmodule OpenAperture.Messaging.AMQP.TestConsumerAsyncSub do

	alias OpenAperture.Messaging.Queue
	alias OpenAperture.Messaging.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options %OpenAperture.Messaging.AMQP.ConnectionOptions{
		username: Application.get_env(:openaperture_amqp, :username),
		password: Application.get_env(:openaperture_amqp, :password),
		virtual_host: Application.get_env(:openaperture_amqp, :virtual_host),
		host: Application.get_env(:openaperture_amqp, :host)
	}
	use OpenAperture.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

	def subscribe() do
		IO.puts("subscribe")
		case subscribe(@queue, fn(payload, _meta, _async_info) -> handle_msg(payload, _meta, _async_info) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def handle_msg(payload, _meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
			OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
			time = :random.uniform(10) * 1000
			:timer.sleep(time)			
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
			OpenAperture.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
		end
	end	
end

defmodule OpenAperture.Messaging.AMQP.TestConsumerAsyncSub2 do
	alias OpenAperture.Messaging.Queue
	alias OpenAperture.Messaging.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options nil
	use OpenAperture.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

	def subscribe() do
		IO.puts("subscribe in TestConsumer2")
		options = %OpenAperture.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:openaperture_amqp, :username),
			password: Application.get_env(:openaperture_amqp, :password),
			virtual_host: Application.get_env(:openaperture_amqp, :virtual_host),
			host: Application.get_env(:openaperture_amqp, :host)
		}

		case subscribe(options, @queue, fn(payload, _meta, _async_info) -> handle_msg(payload, _meta, _async_info) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def handle_msg(payload, _meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
			OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
			time = :random.uniform(10) * 1000
			:timer.sleep(time)
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
			OpenAperture.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
		end
	end		
end


defmodule OpenAperture.Messaging.AMQP.SubscribeAsyncTest do
  use ExUnit.Case
  @moduletag :external

  alias OpenAperture.Messaging.AMQP.TestConsumerAsyncSub
  alias OpenAperture.Messaging.AMQP.TestConsumerAsyncSub2

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe" do
  	OpenAperture.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerAsyncSub.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  

  test "subscribe2" do
  	OpenAperture.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerAsyncSub2.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  
end
