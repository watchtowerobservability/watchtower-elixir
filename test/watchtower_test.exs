defmodule WatchtowerTest do
  use ExUnit.Case

  # Fake key only.
  @key "wtk_example_not_a_real_key"

  test "key header, default endpoint, masked inspect" do
    c = Watchtower.Config.new(service: "svc", key: @key)
    assert Watchtower.Config.headers(c) == [{"authorization", "Bearer " <> @key}]
    assert c.endpoint == "http://localhost:4318"
    refute inspect(c) =~ @key
    assert Watchtower.Config.exporter_env(Watchtower.Config.new(service: "s", endpoint: "https://x.example/"))[:otlp_endpoint] == "https://x.example"
  end

  test "release and environment become resource attributes" do
    c = Watchtower.Config.new(service: "svc", release: "1.2.3", environment: "prod")
    res = Watchtower.Config.otel_env(c)[:resource]
    assert res["service.version"] == "1.2.3"
    assert res["deployment.environment.name"] == "prod"
  end

  test "wt.* attributes are dropped and the redactor can mask or drop" do
    redactor = fn
      {"password", _} -> nil
      {"email", _} -> {"email", "[redacted]"}
      kv -> kv
    end

    Watchtower.put_config(Watchtower.Config.new(service: "s", redactor: redactor))

    out = Watchtower.redact([{"wt.tenant", "t"}, {"password", "x"}, {"email", "a@b.c"}, {"a", 1}])
    assert out == [{"email", "[redacted]"}, {"a", 1}]
  end

  test "exception attributes carry type, message and stack" do
    Watchtower.put_config(Watchtower.Config.new(service: "s"))

    attrs =
      try do
        raise ArgumentError, "bad"
      rescue
        e -> Watchtower.exception_attributes(:error, e, __STACKTRACE__) |> Map.new()
      end

    assert attrs["exception.type"] == "ArgumentError"
    assert attrs["exception.message"] =~ "bad"
    assert attrs["exception.stacktrace"] =~ "watchtower_test"
  end

  test "logger handler classifies crash reasons" do
    stack = [{M, :f, 0, []}]
    assert {:error, %RuntimeError{}, ^stack} = Watchtower.LoggerHandler.crash(%{crash_reason: {%RuntimeError{message: "x"}, stack}})
    assert {:exit, :killed, ^stack} = Watchtower.LoggerHandler.crash(%{crash_reason: {:killed, stack}})
    assert Watchtower.LoggerHandler.crash(%{}) == nil
  end

  test "capture_exception without a recording span does not raise" do
    assert :ok = Watchtower.capture_exception(:error, %RuntimeError{message: "x"}, [])
  end
end
