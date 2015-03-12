#
# == connection_options.ex
#
# This module contains the struct definition for AMQP connection options
#
defmodule CloudOS.Messaging.AMQP.ConnectionOptions do

  @moduledoc """
  This module contains the struct definition for AMQP connection options
  """

	defstruct username: nil, password: nil, host: nil, virtual_host: nil

	defimpl CloudOS.Messaging.ConnectionOptions, for: CloudOS.Messaging.AMQP.ConnectionOptions do

	  @doc """
	  Method to determine the type of options (implementation)

	  ## Options

	  The `options` option containing options struct

	  ## Return Values

	  :amqp
	  """
	  @spec type(any) :: :amqp
	  def type(_) do 
	  	:amqp
	  end

	  @doc """
	  Method to retrieve the implementation-specific options (implementation)

	  ## Options

	  The `options` option containing options struct

	  ## Return Values

	  KeywordList
	  """
	  @spec get(any) :: List
	  def get(options) do
			[
				username: options.username,
				password: options.password,
				host: options.host,
				virtual_host: options.virtual_host
			]	  
		end
	end
end