// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

//solhint-disable func-name-mixedcase

interface ICurvePoolNG {
    function set_oracle(bytes4 methodId, address oracle) external;
}
