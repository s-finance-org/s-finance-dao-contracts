// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SToken.sol";
import "./SLibrary.sol";
import "./InitializableConfigurable.sol";

interface IFarming {
    function farmingETH(address to) external payable returns (uint);
    function unfarmingViaSToken(address underlying, uint amountSToken, address from) external returns (uint, uint);
    function harvestViaSToken(address underlying, address from) external returns (uint, uint);
}

interface ISToken is IERC20 {
    function mint(address to, uint amount) external;
    function burn(address from, uint amount) external;
    function withdrawS(address to, uint amountS) external;
    function withdrawUnderlying(address to, uint amountUnderlying) external;
}

contract SToken is ISToken, Initializable, ERC20 {
    using TransferHelper for address;

	address public farming;
	address public S;
	address public underlying;
	
	constructor(address _S) ERC20('sToken of Payaso Protocol', 'sToken') public {
		initialize('sToken of Payaso Protocol', 'sToken', msg.sender, _S, address(this));
	}
	
	function initialize(string memory name, string memory symbol, address _farming, address _S, address _underlying) public initializer {
	    _name       = name;
	    _symbol     = symbol;
	    farming     = _farming;
	    S        = _S;
	    underlying  = _underlying;
	    IERC20(underlying).totalSupply();
	}
    
    function mint(address to, uint amount) override external {
        require(msg.sender == farming);
        _mint(to, amount);
    }
    
    function burn(address from, uint amount) override external {
        require(msg.sender == farming);
        _burn(from, amount);
    }

    function withdrawS(address to, uint amountS) override external {
        require(msg.sender == farming);
        S.safeTransfer(to, amountS);
    }

    function withdrawUnderlying(address to, uint amountUnderlying) override external {
        require(msg.sender == farming);
        underlying.safeTransfer(to, amountUnderlying);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        if(recipient == address(this) || recipient == farming)
            IFarming(farming).unfarmingViaSToken(underlying, amount, sender);
        else
            super._transfer(sender, recipient, amount);
    }
    
    receive() external payable {
        if(msg.value > 0)
            IFarming(farming).farmingETH{value: msg.value}(msg.sender);
        else
            IFarming(farming).harvestViaSToken(underlying, msg.sender);
    }
} 

contract SFarming is IFarming, InitializableConfigurable {
    using SafeMath for uint;
    using TransferHelper for address;
    using TransferHelper for address payable;

	bytes32 internal constant _WETH_					        = 'WETH';
	bytes32 internal constant _S_					            = 'S';
    bytes32 internal constant _ratioYield_                      = 'ratioYield';
    bytes32 internal constant _sTokenFor_                       = 'sTokenFor';
	bytes32 internal constant _lasttime_					    = 'lasttime';
	bytes32 internal constant _timePrice_					    = 'timePrice';
	bytes32 internal constant _cumulative_					    = 'cumulative';
	bytes32 internal constant _price_					        = 'price';
	bytes32 internal constant _priceEmaN_					    = 'priceEmaN';

    uint totalYield;
    uint totalRebal;
    
    function initialize(address owner, address _addrS) public initializer {
        super.initialize(owner);
        
        config[_WETH_]          = uint(AddressWETH.WETH());
        config[_S_]          = uint(_addrS);
        config[_priceEmaN_]     = 15 minutes;
    }
    
    function sTokenFor(address underlying) public view returns (address sToken) {
        sToken = address(getConfig(_sTokenFor_, underlying));
        require(sToken != address(0) && getConfig(_lasttime_, underlying) > 0, "Not ready to support the underlying token");
    }
    
    function setSTokenFor(address underlying, address sToken) external onlyOwner {
        setConfig(_sTokenFor_, underlying, uint(sToken));
    }
    
    function start(address underlying, uint ratioYield) external onlyOwner {
        if(underlying == address(0))
            underlying = address(config[_WETH_]);
        setConfig(_ratioYield_, underlying, ratioYield);        // 0.1% per day
        setConfig(_lasttime_, underlying, now);
        sTokenFor(underlying);                                  // check sToken != address(0)
    }
    
    struct PriceData {
        uint        p;
        uint        count;
        uint[2]     price;
        uint[2]     cumulative;
        uint32[2]   timestamp;
    }
    
    function _priceFromUniswap(address underlying) internal view returns(PriceData memory r) {          // TWAP * EMA
        if(underlying == address(config[_S_])) {
            r.p = 1 ether;
            r.count = 0;
            return r;
        }

        (r.price[0], r.cumulative[0], r.timestamp[0]) = UniswapV2Library.getPrice(address(config[_S_]), address(config[_WETH_]));
        if(r.timestamp[0] > config[_timePrice_] && config[_timePrice_] > 0) {
            r.price[0] = (r.cumulative[0] - config[_cumulative_]) / (r.timestamp[0] - config[_timePrice_]);                                             // TWAP
            r.price[0] = UniswapV2Library.calcEma(config[_price_], r.price[0], r.timestamp[0] - uint32(config[_timePrice_]), config[_priceEmaN_]);      // EMA
        }
        r.p = r.price[0];
        r.count = 1;

        if(underlying != address(config[_WETH_])) {
            (r.price[1], r.cumulative[1], r.timestamp[1]) = UniswapV2Library.getPrice(address(config[_WETH_]), underlying);
            if(r.timestamp[1] > getConfig(_timePrice_, underlying) && getConfig(_timePrice_, underlying) > 0) {
                r.price[1] = (r.cumulative[1] - getConfig(_cumulative_, underlying)) / (r.timestamp[1] - getConfig(_timePrice_, underlying));                                           // TWAP
                r.price[1] = UniswapV2Library.calcEma(getConfig(_price_, underlying), r.price[1], r.timestamp[1] - uint32(getConfig(_timePrice_, underlying)), config[_priceEmaN_]);    // EMA
            }
            r.p = r.p.mul(r.price[1]).div(1 ether);
            r.count = 2;
        }
    }

    function _updatePriceFromUniswap(address underlying, PriceData memory r) internal {
        if(r.count >= 1) {
            config[_price_]         = r.price[0];
            config[_cumulative_]    = r.cumulative[0];
            config[_timePrice_]     = r.timestamp[0];
            
            if(r.count >= 2) {
                setConfig(_price_,      underlying, r.price[1]);
                setConfig(_cumulative_, underlying, r.cumulative[1]);
                setConfig(_timePrice_,  underlying, r.timestamp[1]);
            }
        }
    }
    
    struct RebalData {
        PriceData   pd;
        address     sToken;
        uint        yieldS;
    }
    
    function _rebalanceCapacity(address underlying) internal view returns (RebalData memory r) {
        r.pd = _priceFromUniswap(underlying);
        r.sToken = sTokenFor(underlying);
        uint lasttime = getConfig(_lasttime_, underlying);
        if(lasttime == now)
            return r;
        r.yieldS = IERC20(config[_S_]).balanceOf(address(this)).mul(now.sub(lasttime)).div(1 days).mul(getConfig(_ratioYield_, underlying)).div(1 ether);
    }
    
    function _rebalance(address underlying, RebalData memory r) internal {
        _updatePriceFromUniswap(underlying, r.pd);
        
        if(r.yieldS > 0) {
            address(config[_S_]).safeTransfer(r.sToken, r.yieldS);
            totalYield = totalYield.add(r.yieldS);
        }

        setConfig(_lasttime_, underlying, now);
        emit Rebalance(underlying, r.yieldS);
    }
    event Rebalance(address indexed underlying, uint yieldS);

    
    function farmingCapacity(address underlying, uint amountUnderlying) public view returns (uint amountSToken) {
        (amountSToken, ) = _farmingCapacity(underlying, amountUnderlying);
    }
    
    function _farmingCapacity(address underlying, uint amountUnderlying) internal view returns (uint amountSToken, RebalData memory r) {
        return __farmingCapacity(underlying, amountUnderlying, _rebalanceCapacity(underlying));
    }
    function __farmingCapacity(address underlying, uint amountUnderlying, RebalData memory r) internal view returns (uint amountSToken, RebalData memory rd) {
        amountSToken = IERC20(config[_S_]).balanceOf(r.sToken);                                      // S.balanceOf( sToken )
        amountSToken = amountSToken.add(r.yieldS);                                                   // + yieldS
        amountSToken = amountSToken.mul(r.pd.p).div(1 ether);                                           // * price,  = the S value in underlying
        amountSToken = amountSToken.add(IERC20(underlying).balanceOf(r.sToken));                        // + underlying.balanceOf( sToken )
        amountSToken = amountUnderlying.mul(IERC20(r.sToken).totalSupply()).div(amountSToken);          // = amountUnderlying * sToken.totalSupply / (market value in underlying)
        rd = r;
    }
    
    function _farming(address underlying, uint amountUnderlying, address from, address to) internal returns (uint amountSToken) {
        RebalData memory r;
        (amountSToken, r) = _farmingCapacity(underlying, amountUnderlying);
        _rebalance(underlying, r);

        underlying.safeTransferFrom(from, r.sToken, amountUnderlying);
        ISToken(r.sToken).mint(to, amountSToken);
        
        emit Farming(underlying, msg.sender, to, amountUnderlying, amountSToken);
    }
    event Farming(address indexed underlying, address indexed from, address indexed to, uint amountUnderlying, uint amountSToken);
    
    function farming(address underlying, uint amountUnderlying, address to) public returns (uint amountSToken) {
        return _farming(underlying, amountUnderlying, msg.sender, to);
    }
    
    function farming(address underlying, uint amountUnderlying) public returns (uint) {
        return _farming(underlying, amountUnderlying, msg.sender, msg.sender);
    }
    
    function farmingETH(address to) virtual override public payable returns (uint) {
        IWETH(config[_WETH_]).deposit{value: msg.value}();
        return _farming(address(config[_WETH_]), msg.value, address(this), to);
    }
    function farmingETH() public payable returns (uint) {
        return farmingETH(msg.sender);
    }

    
    function unfarmingCapacity(address underlying, uint amountSToken) public view returns (uint amountUnderlying, uint amountS) {
        (amountUnderlying, amountS, ) = _unfarmingCapacity(underlying, amountSToken);
    }
    
    function _unfarmingCapacity(address underlying, uint amountSToken) internal view returns (uint amountUnderlying, uint amountS, RebalData memory r) {
        return __unfarmingCapacity(underlying, amountSToken, _rebalanceCapacity(underlying));
    }
    function __unfarmingCapacity(address underlying, uint amountSToken, RebalData memory r) internal view returns (uint amountUnderlying, uint amountS, RebalData memory rd) {
        rd = r;
        uint totalSToken = IERC20(r.sToken).totalSupply();                                              // save gas
        
        amountUnderlying = IERC20(underlying).balanceOf(r.sToken);                                      // underlying.balanceOf( sToken )
        amountUnderlying = amountUnderlying.mul(amountSToken).div(totalSToken);                         // = (underlying remained) * amountSToken / SToken.totalSupply
        
        amountS = IERC20(config[_S_]).balanceOf(r.sToken);                                        // S.balanceOf( sToken )
        amountS = amountS.add(r.yieldS);                                                       // + yieldS
        amountS = amountS.mul(amountSToken).div(totalSToken);                                     // = (underlying remained) * amountSToken / SToken.totalSupply
    }
    
    function _unfarming(address underlying, uint amountSToken, address from, address underTo, address payaTo) internal returns (uint amountUnderlying, uint amountS) {
        RebalData memory r;
        (amountUnderlying, amountS, r) = _unfarmingCapacity(underlying, amountSToken);
        _rebalance(underlying, r);

        ISToken(r.sToken).burn(from, amountSToken);
        ISToken(r.sToken).withdrawUnderlying(underTo, amountUnderlying);
        ISToken(r.sToken).withdrawS(payaTo, amountS);
        
        emit Unfarming(underlying, from, payaTo, amountSToken, amountUnderlying, amountS);
    }
    event Unfarming(address indexed underlying, address indexed from, address indexed to, uint amountSToken, uint amountUnderlying, uint amountS);
    
    function unfarmingViaSToken(address underlying, uint amountSToken, address from) virtual override external returns (uint, uint) {
        require(msg.sender == sTokenFor(underlying), 'Can be called from SToken only');
        return _unfarming(underlying, amountSToken, from, from, from);
    }
    function unfarming(address underlying, uint amountSToken, address to) external returns (uint, uint) {
        return _unfarming(underlying, amountSToken, msg.sender, to, to);
    }
    function unfarming(address underlying, uint amountSToken) external returns (uint, uint) {
        return _unfarming(underlying, amountSToken, msg.sender, msg.sender, msg.sender);
    }
    
    function unfarmingETH(uint amountSToken, address to) public returns (uint amountETH, uint amountS) {
        (amountETH, amountS) = _unfarming(address(config[_WETH_]), amountSToken, msg.sender, address(this), to);
        IWETH(config[_WETH_]).withdraw(amountETH);
        payable(to).transfer(amountETH);
    }
    function unfarmingETH(uint amount) public returns (uint, uint) {
        return unfarmingETH(amount, msg.sender);
    }

    
    function harvestCapacity(address underlying) public view returns (uint amountS, uint amountSToken) {
        (amountS, amountSToken, ) = _harvestCapacity(underlying);
    }
    
    function _harvestCapacity(address underlying) internal view returns (uint amountS, uint amountSToken, RebalData memory r) {
        r = _rebalanceCapacity(underlying);
        amountSToken = IERC20(r.sToken).balanceOf(msg.sender);
        uint amountUnderlying;
        (amountUnderlying, amountS, ) = __unfarmingCapacity(underlying, amountSToken, r);
        (uint amountSTokenNew, ) = __farmingCapacity(underlying, amountUnderlying, r);
        amountSToken = amountSToken.sub(amountSTokenNew);
    }
    
    function _harvest(address underlying, address from, address to) internal returns (uint amountS, uint amountSToken) {
        RebalData memory r;
        (amountS, amountSToken, r) = _harvestCapacity(underlying);
        _rebalance(underlying, r);

        ISToken(r.sToken).burn(from, amountSToken);
        ISToken(r.sToken).withdrawS(to, amountS);
        
        emit Harvest(underlying, from, to, amountS, amountSToken);
    }
    event Harvest(address indexed underlying, address indexed from, address indexed to, uint amountS, uint amountSToken);
    
    function harvestViaSToken(address underlying, address from) virtual override external returns (uint, uint) {
        require(msg.sender == sTokenFor(underlying), 'Can be called from SToken only');
        return _harvest(underlying, from, from);
    }
    function harvest(address underlying, address to) external returns (uint, uint) {
        return _harvest(underlying, msg.sender, to);
    }
    function harvest(address underlying) external returns (uint, uint) {
        return _harvest(underlying, msg.sender, msg.sender);
    }
    
    function harvestETH(address to) external returns (uint, uint) {
        return _harvest(address(config[_WETH_]), msg.sender, to);
    }
    function harvestETH() public returns (uint, uint) {
        return _harvest(address(config[_WETH_]), msg.sender, msg.sender);
    }
    
    receive() external payable {
        if(msg.value > 0)
            farmingETH();
        else
            harvestETH();
    }
}
