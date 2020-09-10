// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SMinter.sol";


contract TestGauge is SSimpleGauge {

	function initialize(address governor, address _minter, address _lp_token, address _rewarded_token) public initializer {
	    super.initialize(governor, _minter, _lp_token);
	    
	    rewarded_token = _rewarded_token;
	    IERC20(_rewarded_token).totalSupply();           // just check
	}
    
    function claim_rewards(address addr) override public {
        rewarded_token.safeTransfer(addr, 10);
    }
    function claimable_reward(address addr) override public view returns (uint) {
        addr;
        return 10;
    }
}


contract TestReward is ERC20 {

	constructor() ERC20("Reward for Test", "Reward") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(msg.sender,  10000 * 10 ** uint256(decimals));
	}
}


contract TestLPToken is ERC20 {

	constructor() ERC20("Underlying for Test", "Underlying") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(msg.sender,  1000000 * 10 ** uint256(decimals));
	}
}


