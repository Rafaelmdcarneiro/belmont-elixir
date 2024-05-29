defmodule Belmont.MemoryTest do
  use ExUnit.Case
  alias Belmont.Memory
  alias Belmont.Cartridge

  describe "new/1" do
    test "zeroes out the ram" do
      memory = Memory.new(%Cartridge{})

      for location <- 0x0000..0x0800 do
        byte = Memory.read_byte(memory, location)
        assert byte == 0x00
      end
    end
  end

  describe "read_byte/2" do
    test "Should be able to read RAM" do
      test_ram = for(_ <- 0..2048, into: [], do: 0xFA) |> List.to_tuple()
      assert 0xFA == %Memory{ram: test_ram} |> Memory.read_byte(0x200)
    end

    test "RAM should be mirrored at 0x800, 0x1000, and 0x2000" do
      test_ram = for(_ <- 0..2048, into: [], do: 0xF0) |> List.to_tuple()

      assert 0xF0 == %Memory{ram: test_ram} |> Memory.read_byte(0x0000)
      assert 0xF0 == %Memory{ram: test_ram} |> Memory.read_byte(0x0800)
      assert 0xF0 == %Memory{ram: test_ram} |> Memory.read_byte(0x1000)
      assert 0xF0 == %Memory{ram: test_ram} |> Memory.read_byte(0x1800)
    end
  end

  describe "read_word/2" do
    test "should be able to read a word from memory" do
      mem =
        %Memory{ram: for(_ <- 0..2048, into: [], do: 0x00) |> List.to_tuple()}
        |> Memory.write_byte(0x0000, 0x31)
        |> Memory.write_byte(0x0001, 0x32)

      assert 0x3231 == Memory.read_word(mem, 0x0000)
    end
  end
end
