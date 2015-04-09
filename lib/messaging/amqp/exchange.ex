#
# == exchange.ex
#
# This module contains definition for an AMQP exchange
#
defmodule OpenAperture.Messaging.AMQP.Exchange do
	
  @moduledoc """
  This module contains definition for an AMQP exchange
  """  

	defstruct name: "", type: :direct, options: [:durable], failover_name: nil

	def get_failover(exchange) do
		%OpenAperture.Messaging.AMQP.Exchange{name: exchange.failover_name, type: exchange.type, options: exchange.options}
	end
end