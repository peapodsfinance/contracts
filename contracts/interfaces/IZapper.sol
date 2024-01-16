// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IZapper {
  enum PoolType {
    V2,
    V3
  }

  struct Pools {
    PoolType poolType; // assume same for both pool1 and pool2
    address pool1;
    address pool2;
  }
}
