#
# == queue.ex
#
# This module contains definition for an AMQP queue
#
defmodule CloudOS.Messaging.Queue do

  @moduledoc """
  This module contains definition for an AMQP queue
  """  

	defstruct name: "", requeue_on_error: true, exchange: %CloudOS.Messaging.AMQP.Exchange{name: nil, type: :direct, options: [:durable]}, error_queue: "", options: [], binding_options: []
end