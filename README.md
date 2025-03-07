<p align="center"><a href="https://gammaswap.com" target="_blank" rel="noopener noreferrer"><img width="100" src="https://app.gammaswap.com/logo.svg" alt="Gammaswap logo"></a></p>

<p align="center">
  <a href="https://github.com/gammaswap/universal-router/actions/workflows/main.yml">
    <img src="https://github.com/gammaswap/universal-router/actions/workflows/main.yml/badge.svg?branch=main" alt="Compile/Test/Publish">
  </a>
</p>

<h1 align="center">Universal Router</h1>
Universal router used to trade across multiple protocols (e.g. DeltaSwap, UniswapV3, Aerodrome, etc.).

## Path Definition

A path is passed to determine that pool sequence swaps will follow to convert an amount of tokenIn to an amount of tokenOut.

Each step in the path is defined as follows

-tokenIn (20 bytes)

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

E.g.

`path = 5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90006000bb82e234DAe75C793f67A35089C9d99245E1C58470b`

-tokenIn: 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9

-protocolId: 0x0006

-fee: 0x000bb8

-tokenOut: 0x2e234DAe75C793f67A35089C9d99245E1C58470b

Paths can be appended to create multi pool paths across multiple protocols.

E.g.

`path = 5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900010000002e234DAe75C793f67A35089C9d99245E1C58470b0006000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a`

-tokenIn: 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9

-protocolId: 0x0001

-fee: 0x000000

-tokenOut: 0x2e234DAe75C793f67A35089C9d99245E1C58470b

-protocolId: 0x0006

-fee: 0x000bb8

-tokenOut: 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a

fee parameter is only needed when swapping with UniswapV3 or Aerodrome Concentrated Liquidity pools.

## Available Protocols
UniswapV2, SushiswapV2, DeltaSwap, UniswapV3, Aerodrome (stable & non-stable), Aerodrome Concentrated Liquidity.

## How to Add Another Protocol Route

Create a contract that implements IProtocolRoute and give it a unique protocolId that has not been used by the protocolRouter yet.
Then add it to the UniversalRouter by calling addProtocolRoute().