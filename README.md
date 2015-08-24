# OpenAperture.Messaging

[![Build Status](https://semaphoreci.com/api/v1/projects/71436c37-54dc-4b06-afd8-0de1a58f541c/394863/badge.svg)](https://semaphoreci.com/perceptive/openaperture_messaging)

This reusable Elixir messaging library provides abstracted methods for interacting with the OpenAperture Messaging system.  

Currently this library utlizes an AMQP client as its primary communication mechanism.  In addition to the base AMQP library, it provides the following features:

* Managed connection pools
* Supervision and reconnection and failover logic for Connections
* Supervision and reconnection and failover logic for Channels
* Synchronous delivery and auto-acknowledgement/rejection of messages
* Asynchronous delivery without acknowledgement of messages (consumer is required to acknowledge/reject)

## Contributing

To contribute to OpenAperture development, view our [contributing guide](http://openaperture.io/dev_resources/contributing.html)

## Usage

The messaging component is defined via the "using" macro, and can be included in other modules.  Remember to add the :openaperture_messaging application to your Elixir application or module.

### Queue

The foundational component of the Messaging system module is a Queue, represented by the OpenAperture.Messaging.Queue struct.  You can cr3eate these structs manually or use the OpenAperture.Messaging.AMQP.QueueBuilder to create and populate the struct for you:

```iex
queue_name = "test_queue"
exchange_id = "1"
queue = OpenAperture.Messaging.AMQP.QueueBuilder.build(OpenAperture.ManagerApi.get_api, queue_name, exchange_id)
```

### Connection Options

#### AMQP Connections

When connecting to an AMQP broker, such as RabbitMQ, you are required to specify the following parameters:

```iex
%OpenAperture.Messaging.AMQP.ConnectionOptions{
  username: "user",
  password: "pass",
  virtual_host: "vhost",
  port: 12345,
  host: "host"
    }
```

You may also specify failover broker connection parameters:

```iex
%OpenAperture.Messaging.AMQP.ConnectionOptions{
  failover_username: "user2",
  failover_password: "pass",
  failover_virtual_host: "vhost",
  failover_port: 12345,
  failover_host: "host2"
    }
```

When specifying a failover connection, make sure to also specify the failover exchange (make sure to specify the name, even if it is the same):

```iex
%OpenAperture.Messaging.AMQP.Exchange{name: "exchange-name", failover_name: "failover-exchange-name"), options: [:durable]}
```

You may utilize the OpenAperture.Messaging.AMQP.ExchangeResolver to cache and quickly retrieve OpenAperture.Messaging.AMQP.Exchange objects as needed, with a simple .get call.  This will resolve both the primary and failover exchange(s).

#### Dynamic Options Resolution

Managing sets of connection options can be complicated.  This library provides a component to help resolve the appropriate connection options:  OpenAperture.Messaging.ConnectionOptionsResolver.

The ConnectionOptionsResolver provides 2 methods to retrieve connections (you must provide a OpenAperture.ManagerApi (api param) with your own server connection information):

* Retrieve connection options for a specific broker

```iex
OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(api, broker_id)
```

* Resolve the connection options between a set of exchanges (and  broker)

```iex
OpenAperture.Messaging.ConnectionOptionsResolver.resolve(api, src_broker_id, src_exchange_id, dest_exchange_id)
```

### Methods

The following methods are currently exposed via the macro:

#### Subscribe Synchronously

When receiving messages from this queue, consumers should take an Elixir mindset of "let is fail".  This module provides some basic requeueing logic that will attempt to requeue the message for another subscriber, in the event an exception is thrown from a callback handler (this behavior can be disabled by setting the requeue_on_error property on a Queue to false).  If exceptions are generated meaning that no consumer can possibly process this message, the consumer should catch these exception and return normally, which will permanently remove the message from the queue.

```iex
subscribe(connection_options \\ @connection_options, queue, callback_handler)
```

The `subscribe` method allows a consumer to receive messages from the messaging system.  The provides 2 arguments, depending on the usage pattern:

* connection_options - OpenAperture.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  This struct can also define the failover connection options.  Defaults to the @connection_options attribute.

* queue - OpenAperture.Messaging.Queue struct, containing the queue (and possibly exchange) information

* callback_handler - A function which receives messages from the queue.  
	* To receive messages synchronously, and auto-acknowledged/rejected, the function must have an arity of 2 (payload, metadata):

```iex
def subscribe() do
	case subscribe(@queue, fn(payload, _meta) -> handle_msg(payload, _meta) end) do
		{:ok, subscription_handler} -> 
			IO.puts("Successfully subscribed to test_queue!")
		{:error, reason} -> 
			IO.puts("Failed to subscribe to test_queue:  #{inspect reason}!")
			:error
	end
end
  	
def handle_msg(payload, meta) do
	IO.puts("TestConsumer:  received message #{inspect payload}")
end
```

#### Subscribe Asynchronously

When receiving messages from a queue, consumers should take an Elixir mindset of "let is fail".  This module provides some basic requeueing logic that will attempt to requeue the message for another subscriber, in the event an exception is thrown from a callback handler (this behavior can be disabled by setting the requeue_on_error property on a Queue to false).  If exceptions are generated meaning that no consumer can possibly process this message, the consumer should catch these exception and return normally, which will permanently remove the message from the queue.  

If exceptions are not generated, the consumer is required to either call OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge() or OpenAperture.Messaging.AMQP.SubscriptionHandler.reject() after processing the message.  If not, the message will be routed to a another consumer.

```iex
subscribe(connection_options \\ @connection_options, queue, callback_handler)
```

* connection_options - OpenAperture.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  This struct can also define the failover connection options.  Defaults to the @connection_options attribute.

* queue - OpenAperture.Messaging.Queue struct, containing the queue (and possibly exchange) information

* callback_handler - A function which receives messages from the queue.  
	* To receive messages asynchronously, and without auto-acknowledgement/rejection, the function must have an arity of 3 (payload, metadata, async_info):

```iex
def subscribe() do
	case subscribe(@queue, fn(payload, _meta, async_info) -> handle_msg(payload, _meta, async_info) end) do
		{:ok, subscription_handler} -> 
			IO.puts("Successfully subscribed to test_queue!")
		{:error, reason} -> 
			IO.puts("Failed to subscribe to test_queue:  #{inspect reason}!")
			:error
	end
end

def handle_msg(payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = async_info) do
	try do
		IO.puts("TestConsumer:  received message #{inspect payload}")
		OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
	rescue e in _ ->
		OpenAperture.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
	end
end
```

#### Unsubscribe

```iex
unsubscribe(connection_options \\ @connection_options, subscription_handler)
```

To unsubscribe from  receiving updates, simply pass the subscription_handler (received during subscription) into the method:

* connection_options - OpenAperture.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  This struct can also define the failover connection options.  Defaults to the @connection_options attribute.

* subscription_handler - SubscriptionHandler (obtained from `subscribe`)

```iex
def unsubscribe() do
	case subscribe(@queue, fn(payload, _meta, async_info) -> handle_msg(payload, _meta, async_info) end) do
		{:ok, subscription_handler} -> 
			IO.puts("Successfully subscribed to test_queue!")

			case unsubscribe(subscription_handler) do
				:ok -> :ok
				{:error, reason} -> IO.puts("Failed to unsubscribe from test_queue:  #{inspect reason}!")
			end
		{:error, reason} -> 
			IO.puts("Failed to subscribe to test_queue:  #{inspect reason}!")
			:error
	end
end

def handle_msg(payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = async_info) do
	try do
		IO.puts("TestConsumer:  received message #{inspect payload}")
		OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
	rescue e in _ ->
		OpenAperture.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
	end
end
```

#### Publish

```iex
publish(connection_options \\ @connection_options, queue, payload)
```

The `publish` method allows a consumer to push messages into the messaging system.  The provides 2/3 arguments, depending on the usage pattern:

* connection_options - OpenAperture.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  This struct can also define the failover connection options.  Defaults to the @connection_options attribute.

* queue - OpenAperture.Messaging.Queue struct, containing the queue (and possibly exchange) information

* payload - The term or primitive you want to publish

#### Close Connection

```iex
close_connection(connection_options \\ @connection_options)
```

The `close_connection` method allows a consumer to close the connection (including subscriptions, channels, and connections) associated with a set of Connection Options

* connection_options - OpenAperture.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  This struct can also define the failover connection options.  Defaults to the @connection_options attribute.

## Usage Patterns

There are two patterns for using messaging:

### Static Connection Configuration

The first pattern is to define static connection configuration that will be used in the messaging component:
 
```iex
defmodule OpenAperture.Messaging.AMQP.TestConsumer do

	alias OpenAperture.Messaging.Queue
	alias OpenAperture.Messaging.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

	#Note that @connection_options must be declared BEFORE the 'use' statement
	@connection_options %OpenAperture.Messaging.AMQP.ConnectionOptions{
		username: Application.get_env(:openaperture_amqp, :username),
		password: Application.get_env(:openaperture_amqp, :password),
		virtual_host: Application.get_env(:openaperture_amqp, :virtual_host),
		host: Application.get_env(:openaperture_amqp, :host),
		port: Application.get_env(:openaperture_amqp, :port),
		failover_username: Application.get_env(:openaperture_amqp, :failover_username),
		failover_password: Application.get_env(:openaperture_amqp, :failover_password),
		failover_virtual_host: Application.get_env(:openaperture_amqp, :failover_virtual_host),
		failover_host: Application.get_env(:openaperture_amqp, :failover_host),
		failover_port: Application.get_env(:openaperture_amqp, :failover_port)
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
```

### Dynamic Connection Configuration

The second pattern is to pass connection configuration into the various methods of the messaging component:

```iex
defmodule OpenAperture.Messaging.AMQP.TestConsumer2 do
	alias OpenAperture.Messaging.Queue
	alias OpenAperture.Messaging.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.ConnectionOptions
	alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

	#Set @connection_options to nil BEFORE the 'use' statement to avoid the warning
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
		options = %OpenAperture.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:openaperture_amqp, :username),
			password: Application.get_env(:openaperture_amqp, :password),
			virtual_host: Application.get_env(:openaperture_amqp, :virtual_host),
			host: Application.get_env(:openaperture_amqp, :host),
			port: Application.get_env(:openaperture_amqp, :port),
			failover_username: Application.get_env(:openaperture_amqp, :failover_username),
			failover_password: Application.get_env(:copenaperture_amqp, :failover_password),
			failover_virtual_host: Application.get_env(:openaperture_amqp, :failover_virtual_host),
			failover_host: Application.get_env(:openaperture_amqp, :failover_host),
			failover_port: Application.get_env(:openaperture_amqp, :failover_port)
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
		options = %OpenAperture.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "rabbitmqhost"
		}

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
```

## Building & Testing

The normal elixir project setup steps are required:

```iex
mix do deps.get, deps.compile
```

You can then run the tests

```iex
MIX_ENV=test mix test test/
```

If you want to run the RabbitMQ system tests (i.e. hit a live system):

1.  Define a new configuration for the "system" environment (config/system.exs) with the following contents:

```
config :openaperture_amqp,
  username: "user",
  password: "pass",
  virtual_host: "env",
  host: "host.myrabbit.com"

config :logger, :console,
  level: :debug
```

2.  Run the following commands on separate machines, able to access the RabbitMQ server:

```iex
MIX_ENV=system mix test test/external/amqp_publish_test.exs --include external:true

#sync processing
MIX_ENV=system mix test test/external/amqp_subscribe_test.exs --include external:true

#async processing
MIX_ENV=system mix test test/external/amqp_subscribe_async_test.exs --include external:true
```
