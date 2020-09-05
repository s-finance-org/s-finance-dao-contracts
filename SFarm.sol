// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SToken.sol";
import "./Governable.sol";

interface IFarm {
    function crop() external view returns (address);
}

interface ISPool {
    event Farming(address indexed farmer, address indexed from, uint amount);
    event Unfarming(address indexed farmer, address indexed to, uint amount);
    event Harvest(address indexed farmer, address indexed to, uint amount);
    
    function setHarvestSpan(uint _span, bool isLinear) external;
    function farming(uint amount) external;
    function farming(address from, uint amount) external;
    function unfarming() external returns (uint amount);
    function unfarming(uint amount) external returns (uint amount_);
    function unfarming(address to, uint amount) external returns (uint amount_);
    function harvest() external returns (uint amount);
    function harvest(address to) external returns (uint amount);
    function harvestCapacity(address farmer) external view returns (uint amount);
}

contract SStakingPool is ISPool, Governable {
    using SafeMath for uint;
    //using TransferHelper for address;

	address public farm;
	address public underlying;
	uint public span;
	uint public end;
	uint public totalStaking;
	mapping(address => uint) public stakingOf;
	mapping(address => uint) public lasttimeOf;
	
	constructor(address _farm, address _underlying) public {
		initialize(msg.sender, _farm, _underlying);
	}
	
	function initialize(address governor, address _farm, address _underlying) public initializer {
	    super.initialize(governor);
	    
	    farm     = _farm;
	    underlying  = _underlying;
	    
	    IFarm(farm).crop();                         // just check
	    IERC20(underlying).totalSupply();           // just check
	}
    
    function setHarvestSpan(uint _span, bool isLinear) virtual override external governance {
        span = _span;
        if(isLinear)
            end = now + _span;
        else
            end = 0;
    }
    
    function farming(uint amount) virtual override external {
        farming(msg.sender, amount);
    }
    function farming(address from, uint amount) virtual override public {
        harvest();
        
        IERC20(underlying).transferFrom(from, address(this), amount);
        stakingOf[msg.sender] = stakingOf[msg.sender].add(amount);
        totalStaking = totalStaking.add(amount);
        
        emit Farming(msg.sender, from, amount);
    }
    
    function unfarming() virtual override external returns (uint amount){
        return unfarming(msg.sender, stakingOf[msg.sender]);
    }
    function unfarming(uint amount) virtual override external returns (uint amount_){
        return unfarming(msg.sender, amount);
    }
    function unfarming(address to, uint amount) virtual override public returns (uint amount_){
        harvest();
        
        totalStaking = totalStaking.sub(amount);
        stakingOf[msg.sender] = stakingOf[msg.sender].sub(amount);
        IERC20(underlying).transfer(to, amount);
        
        emit Unfarming(msg.sender, to, amount);
        return amount;
    }
    
    function harvestCapacity(address farmer) virtual override public view returns (uint amount) {
        if(span == 0 || totalStaking == 0)
            return 0;
        
        amount = IERC20(IFarm(farm).crop()).allowance(farm, address(this));
        amount = amount.mul(stakingOf[farmer]).div(totalStaking);
        
        uint lasttime = lasttimeOf[farmer];
        if(end == 0) {                                                         // isNonLinear, endless
            if(now.sub(lasttime) < span)
                amount = amount.mul(now.sub(lasttime)).div(span);
        }else if(now < end)
            amount = amount.mul(now.sub(lasttime)).div(end.sub(lasttime));
        else if(lasttime >= end)
            amount = 0;
    }
    
    function harvest() virtual override public returns (uint amount) {
        return harvest(msg.sender);
    }
    function harvest(address to) virtual override public returns (uint amount) {
        amount = harvestCapacity(msg.sender);
        if(amount > 0)
            IERC20(IFarm(farm).crop()).transferFrom(farm, to, amount);

        lasttimeOf[msg.sender] = now;

        emit Harvest(msg.sender, to, amount);
    }
} 

contract SFarm is IFarm, Governable {
    address override public crop;

	constructor(address governor, address crop_) public {
		initialize(governor, crop_);
	}
	
    function initialize(address governor, address crop_) public initializer {
        super.initialize(governor);
        crop = crop_;
    }
    
    function approvePool(address pool, uint amount) public governance {
        IERC20(crop).approve(pool, amount);
    }
    
}
