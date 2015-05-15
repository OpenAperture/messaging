#
# == exchange.ex
#
# This module contains definition for an AMQP exchange
#
defmodule OpenAperture.Messaging.AMQP.Exchange do
	
	alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange
  @moduledoc """
  This module contains definition for an AMQP exchange
  """  

	defstruct name: "", 
		type: :direct, 
		options: [:durable],
		routing_key: "", 
		root_exchange_name: "",
		failover_name: nil, 
		failover_routing_key: "", 
		failover_root_exchange_name: "",
		auto_declare: false

	@type t :: %__MODULE__{}

  @doc """
  Method to create a new AMQPExchange that represents the failover configuration

  ## Options

  The `exchange` option represents the primary AMQPExchange configuration

  ## Return Values

  AMQPExchange.t
  """
  @spec get_failover(AMQPExchange.t) :: AMQPExchange.t
	def get_failover(exchange) do
		%OpenAperture.Messaging.AMQP.Exchange{
			name: exchange.failover_name, 
			type: exchange.type, 
	    routing_key: exchange.failover_routing_key,
	    root_exchange_name: exchange.failover_root_exchange_name,
			options: exchange.options
		}
	end

  @doc """
  Method to create a new AMQPExchange from the response of a Manager request

  ## Options

  The `manager_exchange` option represents the Map of values returned by the ManagerApi

  ## Return Values

  AMQPExchange.t
  """
  @spec from_manager_exchange(Map) :: AMQPExchange.t
	def from_manager_exchange(manager_exchange) do
		%OpenAperture.Messaging.AMQP.Exchange{
	    name: manager_exchange["name"],
	    routing_key: manager_exchange["routing_key"],
	    root_exchange_name: manager_exchange["root_exchange_name"],
	    options: [:durable]
		}
	end
end