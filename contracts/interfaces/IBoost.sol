// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IBoost {
    function boost ( uint tokenId ) external;
    function unboost (uint tokenId) external;
}