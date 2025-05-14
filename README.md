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

## Split Multi Path Definition

A split multi path is passed to determine that pool sequence swaps will follow to convert an amount of tokenIn to an amount of tokenOut.

These paths are passed in the externalCall function for rebalancing GammaPool collateral across multiple pools

Each path starts with a weight and is followed by a single path sequence and ended with a 25 byte long zero sequence that serves
as a buffer to identify the next path. There's no need for a buffer zone at the end of the last path.

Every path must have a positive weight and all weights are defined in 18 decimal percentages. Therefore, they must all add up to 1, which in big decimal form is 10^18;

-weight (8 bytes)

-tokenIn (20 bytes)

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

..

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

-zero bytes buffer (25 bytes)

-weight (8 bytes)

-tokenIn (20 bytes)

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

..

-protocolId (2 bytes)

-fee (3 bytes)

-tokenOut (20 bytes)

E.g.

`path = 008e1bc9bf0400000c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e583100000000000000000000000000000000000000000000000000008e1bc9bf0400000c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cee341ebe37e6e2712cb04f5d56de3550000000000000000000000000000000000000000000000000000470de4df8200000c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cee341ebe37e6e2712cb04f5d56de3550001000100f6d9c101ceea72655a13a8cf1c88c1949ed399bc`

In this example the following paths and weights are

`path0 = 0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831`
`path1 = 0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE355`
`path2 = 0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE3550001000100F6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc`

`weight0 = 4e16`
`weight1 = 2e16`
`weight2 = 2e16`

## Available Protocols
UniswapV2, SushiswapV2, DeltaSwap, UniswapV3, Aerodrome (stable & non-stable), Aerodrome Concentrated Liquidity.

## How to Add Another Protocol Route

Create a contract that implements IProtocolRoute and give it a unique protocolId that has not been used by the protocolRouter yet.
Then add it to the UniversalRouter by calling addProtocolRoute().