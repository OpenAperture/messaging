defmodule OpenAperture.Messaging.ConnectionOptionsResolverTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias OpenAperture.ManagerApi
  alias OpenAperture.Messaging.ConnectionOptionsResolver

  setup_all _context do
    :meck.new(OpenAperture.Auth.Client, [:passthrough])
    :meck.expect(OpenAperture.Auth.Client, :get_token, fn _, _, _ -> "abc" end)

    on_exit _context, fn ->
      try do
        :meck.unload OpenAperture.Auth.Client
      rescue _ -> IO.puts "" end
    end    
    :ok
  end
  
  # =========================================
  # get_restrictions_for_exchange tests

  test "get_restrictions_for_exchange - success" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "exchange_brokers", custom: true do
      {brokers, returned_state} = ConnectionOptionsResolver.get_restrictions_for_exchange(state, ManagerApi.get_api, "1")

      assert returned_state != nil
      assert returned_state[:exchanges] != nil
      assert returned_state[:exchanges]["1"] != nil
      assert returned_state[:exchanges]["1"][:broker_restrictions] != nil
      assert returned_state[:exchanges]["1"][:broker_restrictions] == brokers

      is_successful = Enum.reduce brokers, true, fn (broker, is_successful) ->
        if is_successful do
          cond do
            broker["id"] == 1 && broker["name"] == "test" -> true
            broker["id"] == 2 && broker["name"] == "test2" -> true
            true -> false
          end
        else
          is_successful
        end
      end
      assert is_successful == true      
    end
  end

  test "get_restrictions_for_exchange - failure" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "exchange_brokers_failure", custom: true do
      {brokers, returned_state} = ConnectionOptionsResolver.get_restrictions_for_exchange(state, ManagerApi.get_api, "1")

      assert returned_state != nil
      assert returned_state[:exchanges] != nil
      assert returned_state[:exchanges]["1"] != nil
      assert returned_state[:exchanges]["1"][:broker_restrictions] == nil
      assert returned_state[:exchanges]["1"][:broker_restrictions] == brokers

      assert brokers == nil
    end
  end

  test "get_restrictions_for_exchange - success cached" do
    state = %{
      exchanges: %{
        "1" => %{
          retrieval_time: :calendar.universal_time,
          broker_restrictions: []
        }
      },
      brokers: %{}
    }

    {brokers, returned_state} = ConnectionOptionsResolver.get_restrictions_for_exchange(state, ManagerApi.get_api, "1")

    assert returned_state != nil
    assert returned_state[:exchanges] != nil
    assert returned_state[:exchanges]["1"] != nil
    assert returned_state[:exchanges]["1"][:broker_restrictions] != nil
    assert returned_state[:exchanges]["1"][:broker_restrictions] == brokers

    assert brokers == []
  end

  # =========================================
  # resolve_connection_option_for_broker tests

  test "resolve_connection_option_for_broker - success" do
    brokers = [
      %{
        "id" => "1"
      }
    ]

    returned_option = ConnectionOptionsResolver.resolve_connection_option_for_broker(brokers)
    assert returned_option == List.first(brokers)
  end
  

  # =========================================
  # get_connection_option_for_broker tests

  test "get_connection_option_for_broker - success" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections", custom: true do
      {option, returned_state} = ConnectionOptionsResolver.get_connection_option_for_broker(state, ManagerApi.get_api, "1")

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil

      is_successful = cond do
        option["id"] == 1 && option["username"] == "test" -> true
        option["id"] == 2 && option["username"] == "test2" -> true
        true -> false
      end
      assert is_successful == true      
    end
  end

  test "get_connection_option_for_broker - success with failover" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections-with-failover", custom: true do
      {option, returned_state} = ConnectionOptionsResolver.get_connection_option_for_broker(state, ManagerApi.get_api, "1")

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil

      is_successful = cond do
        option["id"] == 1 ->
          assert option["username"] == "test"
          assert option["failover_username"] == "failover"
          true
        option["id"] == 2 ->
          assert option["username"] == "test2" 
          assert option["failover_username"] == "failover"
          true
        true -> false
      end
      assert is_successful == true      
    end
  end

  test "get_connection_option_for_broker - failure" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections_failure", custom: true do
      {option, returned_state} = ConnectionOptionsResolver.get_connection_option_for_broker(state, ManagerApi.get_api, "1")

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] == nil

      assert option == nil
    end
  end

  test "get_connection_option_for_broker - success cached" do
    state = %{
      brokers: %{
        "1" => %{
          retrieval_time: :calendar.universal_time,
          connection_options: [%{}]
        }
      },
      exchanges: %{}
    }

    use_cassette "get_broker", custom: true do
      {option, returned_state} = ConnectionOptionsResolver.get_connection_option_for_broker(state, ManagerApi.get_api, "1")
      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil
      assert option == %{}
    end
  end

  # =========================================
  # get_connection_option_for_brokers tests

  test "get_connection_option_for_brokers - success" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections", custom: true do
      {option, returned_state} = ConnectionOptionsResolver.get_connection_option_for_brokers(state, ManagerApi.get_api, [%{"id"=> "1"}])

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil

      is_successful = cond do
        option["id"] == 1 && option["username"] == "test" -> true
        option["id"] == 2 && option["username"] == "test2" -> true
        true -> false
      end
      assert is_successful == true      
    end
  end  

  #=========================
  # cache_stale? tests

  test "cache_stale? - no time" do
    state = %{}
    assert ConnectionOptionsResolver.cache_stale?(state) == true
  end

  test "cache_stale? - expired" do
    seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
    seconds = seconds - 301

    state = %{
      retrieval_time: :calendar.gregorian_seconds_to_datetime(seconds)
    }
    assert ConnectionOptionsResolver.cache_stale?(state) == true
  end

  test "cache_stale? - valid" do
    state = %{
      retrieval_time: :calendar.universal_time
    }
    assert ConnectionOptionsResolver.cache_stale?(state) == false
  end

  #=========================
  # handle_call({:resolve}) tests  

  test "handle_call({:resolve}) - no restrictions" do
    use_cassette "resolve-no-restrictions", custom: true do
      state = %{
        exchanges: %{},
        brokers: %{}
      }

      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:resolve, ManagerApi.get_api, "1", "1", "2"}, %{}, state)
      assert connection_option != nil
      assert (connection_option.username == "test" || connection_option.username == "test2")

      assert returned_state != nil
    end
  end

  test "handle_call({:resolve}) - src restrictions" do
    use_cassette "resolve-src-restrictions", custom: true do
      state = %{
        exchanges: %{},
        brokers: %{}
      }

      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:resolve, ManagerApi.get_api, "1", "1", "2"}, %{}, state)
      assert connection_option != nil
      assert (connection_option.username == "test" || connection_option.username == "test2")

      assert returned_state != nil
    end
  end  

  test "handle_call({:resolve}) - src and dst restrictions" do
    use_cassette "resolve-srcdst-restrictions", custom: true do
      state = %{
        exchanges: %{},
        brokers: %{}
      }

      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:resolve, ManagerApi.get_api, "1", "1", "2"}, %{}, state)
      assert connection_option != nil
      assert (connection_option.username == "test" || connection_option.username == "test2")

      assert returned_state != nil
    end
  end  

  test "handle_call({:resolve}) - dst restrictions" do
    use_cassette "resolve-dst-restrictions", custom: true do
      state = %{
        exchanges: %{},
        brokers: %{}
      }

      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:resolve, ManagerApi.get_api, "1", "1", "2"}, %{}, state)
      assert connection_option != nil
      assert (connection_option.username == "test" || connection_option.username == "test2")

      assert returned_state != nil
    end
  end  

  # =========================================
  # handle_call({:get_for_broker}) tests

  test "handle_call({:get_for_broker}) - success" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections", custom: true do
      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:get_for_broker, ManagerApi.get_api, "1"}, %{}, state)

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil
      assert returned_state[:brokers]["1"][:connection_options] != nil

      is_successful = cond do
        connection_option.id == 1 && connection_option.username == "test" -> true
        connection_option.id == 2 && connection_option.username == "test2" -> true
        true -> false
      end
      assert is_successful == true      
    end
  end

  test "handle_call({:get_for_broker}) - failure" do
    state = %{
      exchanges: %{},
      brokers: %{}
    }

    use_cassette "get_broker_connections_failure", custom: true do
      {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:get_for_broker, ManagerApi.get_api, "1"}, %{}, state)

      assert returned_state != nil
      assert returned_state[:brokers] != nil
      assert returned_state[:brokers]["1"] != nil
      assert returned_state[:brokers]["1"][:connection_options] == nil

      assert connection_option == nil
    end
  end

  test "handle_call({:get_for_broker}) - success cached" do
    state = %{
      brokers: %{
        "1" => %{
          retrieval_time: :calendar.universal_time,
          connection_options: [%{}]
        }
      },
      exchanges: %{}
    }

    {:reply, connection_option, returned_state} = ConnectionOptionsResolver.handle_call({:get_for_broker, ManagerApi.get_api, "1"}, %{}, state)

    assert returned_state != nil
    assert returned_state[:brokers] != nil
    assert returned_state[:brokers]["1"] != nil
    assert returned_state[:brokers]["1"][:connection_options] != nil
    assert connection_option == %OpenAperture.Messaging.AMQP.ConnectionOptions{}
  end    
end

