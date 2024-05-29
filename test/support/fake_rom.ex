defmodule Belmont.FakeROM do
  @moduledoc """
  Generate a fake rom for testing    
  """

  @defaults %{
    prg_rom_data_override: [],
    fill_prg_rom_start: 0x00,
    fill_chr_rom_start: 0x00,
    prg_rom_banks_count: 1,
    chr_rom_banks_count: 1,
    prg_ram_banks_count: 1,
    mapper: 0,
    mirroring_mode: :horizontal,
    battery_backed_ram: 0,
    trainer_present: 0
  }

  @doc """
  Generates a fake rom for unit tests
  """
  def rom(options \\ []) do
    %{
      fill_prg_rom_start: fill_prg_rom_start,
      prg_rom_data_override: prg_rom_data_override,
      fill_chr_rom_start: fill_chr_rom_start,
      prg_rom_banks_count: prg_rom_banks_count,
      chr_rom_banks_count: chr_rom_banks_count,
      prg_ram_banks_count: prg_ram_banks_count,
      mapper: mapper,
      mirroring_mode: mirroring_mode,
      battery_backed_ram: battery_backed_ram,
      trainer_present: trainer_present
    } = Enum.into(options, @defaults)

    # Mapper, mirroring, battery, trainer
    <<upper_mapper::4, lower_mapper::4>> = <<mapper>>

    {mirroring_bit, four_screen_mirroring} =
      case mirroring_mode do
        :horizontal -> {0, 0}
        :vertical -> {1, 0}
        _ -> {0, 1}
      end

    flag6 = <<lower_mapper::4, four_screen_mirroring::1, trainer_present::1, battery_backed_ram::1, mirroring_bit::1>>

    # Mapper, VS/Playchoice, NES 2.0
    flag7 = <<upper_mapper::4, 0::1, 0::1, 0::1, 0::1>>

    # header
    header =
      <<0x4E, 0x45, 0x53, 0x1A, prg_rom_banks_count, chr_rom_banks_count>> <>
        flag6 <> flag7 <> <<prg_ram_banks_count, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0>>

    # game data, just fill it with 0
    trainer_bytes =
      if trainer_present == 1 do
        for _ <- 1..512, into: <<>>, do: <<0>>
      else
        <<>>
      end

    prg_data =
      for i <- 1..prg_rom_banks_count, into: <<>> do
        for byte_loc <- 1..16_384, into: <<>> do
          override =
            Enum.find(prg_rom_data_override, fn x ->
              x[:bank] == i - 1 && x[:location] == byte_loc - 1
            end)

          if override == nil do
            <<fill_prg_rom_start + i - 1>>
          else
            <<override[:value]>>
          end
        end
      end

    chr_data =
      for i <- 1..chr_rom_banks_count, into: <<>> do
        for _ <- 1..8_192, into: <<>> do
          <<fill_chr_rom_start + i - 1>>
        end
      end

    game_data = trainer_bytes <> prg_data <> chr_data

    header <> game_data
  end
end
