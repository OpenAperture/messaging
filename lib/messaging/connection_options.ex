#
# == connection_options.ex
#
# This module contains the protocol definition for Messaging connection options
#
defprotocol OpenAperture.Messaging.ConnectionOptions do

  @moduledoc """
  This module contains the protocol definition for Messaging connection options
  """

  @doc """
  Method to determine the type of options

  ## Options

  The `options` option containing options struct

  ## Return Values

  The atom representing the options implementation
  """
  @spec type(any) :: term
	def type(options)

  @doc """
  Method to retrieve the implementation-specific options

  ## Options

  The `options` option containing options struct

  ## Return Values

  The implementation-specific options term
  """
  @spec get(any) :: term
  def get(options)
end