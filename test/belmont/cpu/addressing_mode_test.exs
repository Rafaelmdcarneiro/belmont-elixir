defmodule Belmont.CPU.AddressingModeTest do
  use ExUnit.Case
  alias Belmont.FakeROM
  alias Belmont.Memory
  alias Belmont.CPU
  alias Belmont.Cartridge

  test "Zero page addressing should return an address pointed to by the program counter + 1 (+ register for indexed)" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x02]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> CPU.set_register(:x, 0x03)
      |> CPU.set_register(:y, 0xFF)
      |> Map.put(:program_counter, 0x8000)

    # zero page
    address = Belmont.CPU.AddressingMode.get_address(:zero_page, cpu)
    assert address.address == 0x02
    assert address.page_crossed == false

    # x indexed
    address = Belmont.CPU.AddressingMode.get_address(:zero_page_x, cpu)
    assert address.address == 0x05
    assert address.page_crossed == false

    # y indexed
    address = Belmont.CPU.AddressingMode.get_address(:zero_page_y, cpu)
    assert address.address == 0x01
    assert address.page_crossed == false
  end

  test "Absolute addressing should return an address pointed to by the program counter + 1 (+ register for indexed)" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x02],
          [bank: 0, location: 0x0002, value: 0x03]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> CPU.set_register(:x, 0x03)
      |> CPU.set_register(:y, 0xFF)
      |> Map.put(:program_counter, 0x8000)

    # absolute
    address = Belmont.CPU.AddressingMode.get_address(:absolute, cpu)
    assert address.address == 0x0302
    assert address.page_crossed == false

    # x indexed
    address = Belmont.CPU.AddressingMode.get_address(:absolute_x, cpu)
    assert address.address == 0x0305
    assert address.page_crossed == false

    # y indexed
    address = Belmont.CPU.AddressingMode.get_address(:absolute_y, cpu)
    assert address.address == 0x0401
    assert address.page_crossed
  end

  test "Indirect addressing should return an indirect address" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x03],
          [bank: 0, location: 0x0002, value: 0x80],
          [bank: 0, location: 0x0003, value: 0x11],
          [bank: 0, location: 0x0004, value: 0x31]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> Map.put(:program_counter, 0x8000)

    address = Belmont.CPU.AddressingMode.get_address(:indirect, cpu)
    assert address.address == 0x3111
    assert address.page_crossed == false
  end

  test "Indexed Indirect addressing should return an address + x register" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0xA1],
          [bank: 0, location: 0x0001, value: 0x20]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> Memory.write_byte(0x24, 0x74)
      |> Memory.write_byte(0x25, 0x20)
      |> CPU.new()
      |> CPU.set_register(:x, 0x04)
      |> Map.put(:program_counter, 0x8000)

    address = Belmont.CPU.AddressingMode.get_address(:indexed_indirect, cpu)
    assert address.address == 0x2074
    assert address.page_crossed == false
  end

  test "Indirect Indexed addressing should return an address + y register" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0xB1],
          [bank: 0, location: 0x0001, value: 0x86]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> Memory.write_byte(0x86, 0x28)
      |> Memory.write_byte(0x87, 0x40)
      |> CPU.new()
      |> CPU.set_register(:y, 0x10)
      |> Map.put(:program_counter, 0x8000)

    address = Belmont.CPU.AddressingMode.get_address(:indirect_indexed, cpu)
    assert address.address == 0x4038
    assert address.page_crossed == false
  end

  test "immediate addressing should return the address after the program counter" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x02],
          [bank: 0, location: 0x0002, value: 0x03]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> CPU.set_register(:x, 0x03)
      |> CPU.set_register(:y, 0xFF)
      |> Map.put(:program_counter, 0x8000)

    # absolute
    address = Belmont.CPU.AddressingMode.get_address(:immediate, cpu)
    assert address.address == 0x8001
    assert address.page_crossed == false
  end

  test "relative address should return the correct address and consider the byte signed" do
    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x02]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> Map.put(:program_counter, 0x8000)

    address = Belmont.CPU.AddressingMode.get_address(:relative, cpu)
    assert address.address == 0x8004
    assert address.page_crossed == false

    cpu =
      FakeROM.rom(
        prg_rom_data_override: [
          [bank: 0, location: 0x0000, value: 0x01],
          [bank: 0, location: 0x0001, value: 0x82]
        ]
      )
      |> Cartridge.parse_rom_contents!()
      |> Memory.new()
      |> CPU.new()
      |> Map.put(:program_counter, 0x8000)

    address = Belmont.CPU.AddressingMode.get_address(:relative, cpu)
    assert address.address == 0x7F84
    assert address.page_crossed == false
  end
end
