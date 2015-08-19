#
# == connection_options.ex
#
# This module contains the struct definition for AMQP connection options
#
defmodule OpenAperture.Messaging.AMQP.ConnectionOptions do

  @moduledoc """
  This module contains the struct definition for AMQP connection options
  """

  @type t :: %__MODULE__{}
	defstruct id: nil,
    username: nil,
    password: nil,
    host: nil,
    port: nil,
    virtual_host: nil,
    heartbeat: 60,
    failover_id: nil,
    failover_username: nil,
    failover_password: nil,
    failover_host: nil,
    failover_port: nil,
    failover_virtual_host: nil,
    failover_heartbeat: 60

  @doc """
  Method to convert a Map into the ConnectionOptions struct

  ## Options

  The `map` option defines the raw Map

  ## Return Values

  String
  """
  @spec from_map(map) :: OpenAperture.Messaging.AMQP.ConnectionOptions.t
  def from_map(map) do
    %OpenAperture.Messaging.AMQP.ConnectionOptions{
      id: map["id"],
      username: map["username"],
      password: map["password"],
      host: map["host"],
      port: map["port"],
      virtual_host: map["virtual_host"],
      heartbeat: map["heartbeat"] || 60,
      failover_id: map["failover_id"],
      failover_username: map["failover_username"],
      failover_password: map["failover_password"],
      failover_host: map["failover_host"],
      failover_port: map["failover_port"],
      failover_virtual_host: map["failover_virtual_host"],
      failover_heartbeat: map["failover_heartbeat"] || 60,
    }
  end

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
        port = case Keyword.get(options, :port) do
        	nil -> ""
					raw_port -> ":#{raw_port}"
        end
        "amqp://#{user}:#{password}@#{host}#{port}/#{virtual_host}"
      connection_url -> connection_url
    end
	end

	defimpl OpenAperture.Messaging.ConnectionOptions, for: OpenAperture.Messaging.AMQP.ConnectionOptions do

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
	  @spec get(OpenAperture.Messaging.AMQP.ConnectionOptions.t) :: list
	  def get(options) do
			[
				username: options.username,
				password: options.password,
				host: options.host,
				port: options.port,
				virtual_host: options.virtual_host,
        heartbeat: options.heartbeat
			]
		end
	end
end
