defmodule Belmont.Mapper.NROMTest do
  use ExUnit.Case
  alias Belmont.FakeROM
  alias Belmont.Memory
  alias Belmont.Cartridge
  alias Belmont.Mapper.NROM

  describe "inital rom banks" do
    test "2 prg-rom bank rom the lower bank should be the first and the upper the second" do
      rom = FakeROM.rom(prg_rom_banks_count: 2, prg_ram_banks_count: 1, chr_rom_banks_count: 1)
      {:ok, cart} = Cartridge.parse_rom_contents(rom)

      assert NROM.initial_lower_bank(cart) == 0
      assert NROM.initial_upper_bank(cart) == 1
    end

    test "1 prg-rom bank rom the lower and upper bank should be the single bank" do
      rom = FakeROM.rom(prg_rom_banks_count: 1, prg_ram_banks_count: 1, chr_rom_banks_count: 1)
      {:ok, cart} = Cartridge.parse_rom_contents(rom)

      assert NROM.initial_lower_bank(cart) == 0
      assert NROM.initial_upper_bank(cart) == 0
    end
  end

  test "read_byte/2 reads from the appropriate bank" do
    rom = FakeROM.rom(prg_rom_banks_count: 2, prg_ram_banks_count: 1, chr_rom_banks_count: 1, fill_prg_rom_start: 0x01)
    {:ok, cart} = Cartridge.parse_rom_contents(rom)
    memory = Memory.new(cart)

    assert NROM.read_byte(memory, 0x800F) == 0x01
    assert NROM.read_byte(memory, 0xC0F0) == 0x02
  end
end
