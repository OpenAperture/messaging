#
# == queue.ex
#
# This module contains definition for an AMQP queue
#
defmodule OpenAperture.Messaging.Queue do

  @moduledoc """
  This module contains definition for an AMQP queue
  """  

	defstruct name: "", 
		requeue_on_error: true, 
		exchange: %OpenAperture.Messaging.AMQP.Exchange{
			name: nil, 
			type: :direct, options: [:durable]
		}, 
		error_queue: "", 
		options: [], 
		binding_options: [],
		auto_declare: false

	@type t :: %__MODULE__{}
end