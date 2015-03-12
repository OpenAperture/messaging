#
# == exchange.ex
#
# This module contains definition for an AMQP exchange
#
defmodule CloudOS.Messaging.AMQP.Exchange do
	
  @moduledoc """
  This module contains definition for an AMQP exchange
  """  

	defstruct name: "", type: :direct, options: [:durable]
end