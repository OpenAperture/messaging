#
# == connection_options.ex
#
# This module contains the struct definition for AMQP connection options
#
defmodule CloudOS.Messaging.AMQP.ConnectionOptions do

  @moduledoc """
  This module contains the struct definition for AMQP connection options
  """

	defstruct username: nil, password: nil, host: nil, virtual_host: nil, failover_username: nil, failover_password: nil, failover_host: nil, failover_virtual_host: nil

  @doc """
  Method to retrieve the implementation-specific connection URL

  ## Options

  The `options` option containing options struct

  ## Return Values

  String
  """
  @spec get_connection_url(any) :: String
	def get_connection_url(options) do
		case Keyword.get(options, :connection_url, nil) do
      nil ->
        #build a url:  amqp://user:pass@host/vhost
        user = Keyword.get(options, :username, "")
        password = Keyword.get(options, :password, "")
        host = Keyword.get(options, :host, "")
        virtual_host = Keyword.get(options, :virtual_host, "")
        "amqp://#{user}:#{password}@#{host}/#{virtual_host}"
      connection_url -> connection_url			
    end
	end

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