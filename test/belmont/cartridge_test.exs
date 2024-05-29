defmodule Belmont.CartridgeTest do
  use ExUnit.Case
  alias Belmont.Cartridge
  alias Belmont.FakeROM

  describe "parsing a rom header" do
    test "an invalid header should return an error" do
      assert {:error, _message} = Cartridge.parse_rom_contents(<<1, 2, 3, 4, 5>>)
    end

    test "game data sizes" do
      rom = FakeROM.rom(prg_rom_banks_count: 8, prg_ram_banks_count: 6, chr_rom_banks_count: 16)
      assert {:ok, cart} = Cartridge.parse_rom_contents(rom)
      assert cart.prg_rom_banks_count == 8
      assert cart.prg_ram_banks_count == 6
      assert cart.chr_rom_banks_count == 16
    end

    test "mapper parsing" do
      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mapper: 4))
      assert cart.mapper == 4

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mapper: 2))
      assert cart.mapper == 2

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mapper: 1))
      assert cart.mapper == 1

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mapper: 0))
      assert cart.mapper == 0
    end

    test "mirroring mode" do
      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mirroring_mode: :horizontal))
      assert cart.mirroring_mode == :horizontal

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mirroring_mode: :vertical))
      assert cart.mirroring_mode == :vertical

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(mirroring_mode: :four_screen))
      assert cart.mirroring_mode == :four_screen
    end

    test "battery backed persistence flag" do
      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(battery_backed_ram: 1))
      assert cart.battery_backed_ram

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(battery_backed_ram: 0))
      assert !cart.battery_backed_ram
    end

    test "trainer present" do
      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(trainer_present: 1))
      assert cart.trainer_present

      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(trainer_present: 0))
      assert !cart.trainer_present
    end

    test "0 program ram banks actually means 1 is found" do
      assert {:ok, cart} = Cartridge.parse_rom_contents(FakeROM.rom(prg_ram_banks_count: 0))
      assert cart.prg_ram_banks_count == 1
    end
  end

  describe "parsing the game data" do
    test "if a trainer is present the first 512 bytes should be ignored" do
      {:ok, cart} =
        FakeROM.rom(trainer_present: 1, fill_prg_rom_start: 0x01, fill_chr_rom_start: 0x01)
        |> Cartridge.parse_rom_contents()

      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(16_383)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(8_191)
    end

    test "if a trainer is not present don't ignore the first 512 bytes" do
      {:ok, cart} =
        FakeROM.rom(trainer_present: 0, fill_prg_rom_start: 0x01, fill_chr_rom_start: 0x01)
        |> Cartridge.parse_rom_contents()

      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(16_383)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(8_191)
    end

    test "multiple program and character rom banks should be read" do
      {:ok, cart} =
        FakeROM.rom(prg_rom_banks_count: 2, chr_rom_banks_count: 4, fill_prg_rom_start: 0x01, fill_chr_rom_start: 0x01)
        |> Cartridge.parse_rom_contents()

      assert length(cart.prg_rom_banks) == 2
      assert length(cart.chr_rom_banks) == 4
      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.prg_rom_banks |> List.first() |> elem(16_383)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(0)
      assert 0x01 == cart.chr_rom_banks |> List.first() |> elem(8_191)
    end
  end
end
