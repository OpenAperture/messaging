defmodule CloudOS.Messaging.AMQP.ConnectionOptionsTest do
  use ExUnit.Case, async: false

  alias CloudOS.Messaging.ConnectionOptions
  alias CloudOS.Messaging.AMQP.ConnectionOptions, as: AMQPOptions

  test "convert empty struct to list" do
    options = %AMQPOptions{}
    options_list = ConnectionOptions.get(options)
    assert options_list != nil
    assert Keyword.get(options_list, :username) == nil
    assert Keyword.get(options_list, :password) == nil
    assert Keyword.get(options_list, :host) == nil
    assert Keyword.get(options_list, :virtual_host) == nil
  end

  test "convert struct to list" do
    options = %AMQPOptions{
    	username: "test",
    	password: "123abc",
    	host: "test_host",
    	virtual_host: "vhost"
    }
    options_list = ConnectionOptions.get(options)
    assert options_list != nil
    assert Keyword.get(options_list, :username) == options.username
    assert Keyword.get(options_list, :password) == options.password
    assert Keyword.get(options_list, :host) == options.host
    assert Keyword.get(options_list, :virtual_host) == options.virtual_host
  end  
end