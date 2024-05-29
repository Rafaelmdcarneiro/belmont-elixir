defmodule Belmont.HexstrTest do
  use ExUnit.Case
  alias Belmont.Hexstr

  describe "hex/2" do
    test "handles 2 digit hex strings" do
      assert Hexstr.hex(255, 2) == "FF"
    end

    test "handles 4 digit hex strings with leading zeros" do
      assert Hexstr.hex(1234, 4) == "04D2"
    end
  end
end
