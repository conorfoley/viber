defmodule Viber.Runtime.SignatureTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Signature
  alias Viber.Runtime.Signature.{Field, ParseError}

  @spec_text "diff, goal -> verdict: enum[passed,failed], evidence: list[string], score: int, done: bool, notes"

  describe "new/2" do
    test "parses inputs, outputs and types" do
      assert {:ok, sig} = Signature.new(@spec_text, name: "verdict")

      assert [%Field{name: "diff", type: :string}, %Field{name: "goal"}] = sig.inputs

      assert [
               %Field{name: "verdict", type: {:enum, ["passed", "failed"]}},
               %Field{name: "evidence", type: {:list, :string}},
               %Field{name: "score", type: :integer},
               %Field{name: "done", type: :boolean},
               %Field{name: "notes", type: :string}
             ] = sig.outputs
    end

    test "allows no inputs" do
      assert {:ok, %Signature{inputs: [], outputs: [_]}} = Signature.new("-> answer")
    end

    test "rejects bad specs" do
      assert {:error, _} = Signature.new("a, b")
      assert {:error, _} = Signature.new("a ->")
      assert {:error, _} = Signature.new("a -> b: widget")
      assert {:error, _} = Signature.new("a -> Bad-Name")
      assert {:error, _} = Signature.new("a -> a")
      assert {:error, _} = Signature.new("a -> b: enum[]")
      assert {:error, _} = Signature.new("a -> b", name: "no spaces allowed")
    end

    test "new!/2 raises on a bad spec" do
      assert_raise ArgumentError, fn -> Signature.new!("nope") end
    end

    test "attaches descriptions" do
      sig = Signature.new!("-> answer", descriptions: %{"answer" => "the answer"})
      assert %{"description" => "the answer"} = Signature.json_schema(sig)["properties"]["answer"]
    end
  end

  test "json_schema/1 and tool_definition/1" do
    sig = Signature.new!(@spec_text, name: "verdict")
    schema = Signature.json_schema(sig)

    assert schema["required"] == ["verdict", "evidence", "score", "done", "notes"]

    assert schema["properties"]["verdict"] == %{
             "type" => "string",
             "enum" => ["passed", "failed"]
           }

    assert schema["properties"]["evidence"] == %{
             "type" => "array",
             "items" => %{"type" => "string"}
           }

    assert %{name: "submit_verdict", input_schema: ^schema} = Signature.tool_definition(sig)
  end

  describe "validate/2" do
    setup do
      {:ok, sig: Signature.new!(@spec_text, name: "verdict")}
    end

    test "accepts a valid reply", %{sig: sig} do
      reply = %{
        "verdict" => " passed ",
        "evidence" => ["ran tests"],
        "score" => 3.0,
        "done" => true,
        "notes" => ""
      }

      assert {:ok, %{"verdict" => "passed", "score" => 3, "evidence" => ["ran tests"]}} =
               Signature.validate(sig, reply)
    end

    test "reports missing fields", %{sig: sig} do
      assert {:error, %ParseError{kind: :missing_fields, fields: ["evidence", "score", "done"]}} =
               Signature.validate(sig, %{"verdict" => "passed", "notes" => "x"})
    end

    test "reports invalid fields", %{sig: sig} do
      reply = %{
        "verdict" => "maybe",
        "evidence" => ["ok", 1],
        "score" => 1,
        "done" => "yes",
        "notes" => "x"
      }

      assert {:error, %ParseError{kind: :invalid_fields, fields: fields, message: msg}} =
               Signature.validate(sig, reply)

      assert fields == ["verdict", "evidence", "done"]
      assert msg =~ "verdict must be one of passed, failed"
    end

    test "rejects a non-map", %{sig: sig} do
      assert {:error, %ParseError{kind: :malformed}} = Signature.validate(sig, "nope")
    end
  end

  describe "decode/2" do
    setup do
      {:ok, sig: Signature.new!("-> answer: int")}
    end

    test "plain, fenced and embedded JSON", %{sig: sig} do
      assert {:ok, %{"answer" => 1}} = Signature.decode(sig, ~s({"answer": 1}))
      assert {:ok, %{"answer" => 2}} = Signature.decode(sig, "```json\n{\"answer\": 2}\n```")
      assert {:ok, %{"answer" => 3}} = Signature.decode(sig, ~s(Sure! {"answer": 3} done))
    end

    test "non-JSON is malformed", %{sig: sig} do
      assert {:error, %ParseError{kind: :malformed}} = Signature.decode(sig, "no idea")
    end
  end

  test "format_inputs/2" do
    sig = Signature.new!("goal, files -> answer")

    assert Signature.format_inputs(sig, %{"files" => ["a.ex"], goal: "fix it"}) ==
             "<goal>\nfix it\n</goal>\n\n<files>\n[\"a.ex\"]\n</files>"
  end
end
