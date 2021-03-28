// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.0;

library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
}

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    if (a == 0) {
      return 0;
    }
    c = a * b;
    assert(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}

library Math {
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IPair {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 timestamp);
}

interface IRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external view returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

contract TokenBase is IERC20 {
    using SafeMath for uint;
    
    string private _name = "PNToken";
    string private _symbol = "PNT";
    uint8 private _decimals = 18;
    uint256 public _totalSupply;
    mapping (address => uint256) public _balances;
    mapping (address => mapping (address => uint256)) public _allowances;
    
    event Mint(address indexed owner, uint indexAmount, uint amount0, uint amount1);
    event Burn(address indexed owner, uint indexAmount, uint amount0, uint amount1);

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        if (_balances[msg.sender] >= _value && _value > 0) {
            _balances[msg.sender] = _balances[msg.sender].sub(_value);
            _balances[_to] = _balances[_to].add(_value);
            emit Transfer(msg.sender, _to, _value);
            return true;
        } else { 
            return false;
        }
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        if (_balances[_from] >= _value && _allowances[_from][msg.sender] >= _value && _value > 0) {
            _balances[_to] = (_balances[_to]).add(_value);
            _balances[_from] = _balances[_from].sub(_value);
            _allowances[_from][msg.sender] = _allowances[_from][msg.sender].sub(_value);
            emit Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function balanceOf(address _owner) public override view returns (uint256 balance) {
        return _balances[_owner];
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public override view returns (uint256 remaining) {
        return _allowances[_owner][_spender];
    }
    
    function totalSupply() public override view returns (uint256 total) {
        return _totalSupply;
    }
}

contract PNIndex is TokenBase {
    using SafeMath for uint;

    address immutable public token0;
    address immutable public token1;
    IPair immutable public pair;
    IRouter immutable public router;
    
    constructor(
        address _token0, 
        address _token1,
        address _pair,
        address _router
    ) {
        token0 = _token0;
        token1 = _token1;
        pair = IPair(_pair);
        router = IRouter(_router);
    }
    
    function mint(uint amount0, uint amount1) public returns (uint256 indexAmount, uint256 amount0S, uint256 amount1S) {
        require(amount1 != 0, "Token1 amount is equal to zero.");
        require(amount0 != 0, "Token0 amount is equal to zero.");
        (uint256 amount0R, uint256 amount1R,) = pair.getReserves();
        amount1S = (amount0.div(2)).mul(amount1R).div(amount0R);
        
        if(amount1S < amount1) {
            amount0S = amount0;
            indexAmount =  _mint(amount0, amount1S);
        } else {
            amount0S = (amount1.mul(2)).mul(amount0R).div(amount1R);
            amount1S = amount1;
            indexAmount =  _mint(amount0S, amount1);
        }
    }
    
    function mintAndConvert(uint amount, address convertToken) public returns (uint indexAmount) {
        uint256 amount0 = amount.mul(2).div(3);
        uint256 amount1 = amount.div(3);
        address[] memory addresses = new address[](2);
        addresses[0] = convertToken;
        addresses[1] = token0; 
        uint256[] memory amounts0 = router.swapExactTokensForTokens(amount0, 0, addresses, msg.sender, block.timestamp + 3600);
        addresses[1] = token1; 
        uint256[] memory amounts1 = router.swapExactTokensForTokens(amount1, 0, addresses, msg.sender, block.timestamp + 3600);
        uint256 amount0S;
        uint256 amount1S;
        (indexAmount, amount0S, amount1S) = mint(amounts0[1], amounts1[1]);
        
        if(amount0S < amounts0[1]) {
            TransferHelper.safeTransfer(token0, msg.sender, amounts0[1] - amount0S);
        }
        
        if(amount1S < amounts1[1]) {
            TransferHelper.safeTransfer(token1, msg.sender, amounts1[1] - amount1S);
        }
    }
    
    function burn(uint256 amount) public returns (uint256 amount0, uint256 amount1) {
        require(amount != 0, "Index token amount is equal to zero.");
        require(_balances[msg.sender] >= amount, "Not enough index token.");
        (amount0, amount1) = getBurnAmount(amount);
        TransferHelper.safeTransfer(token0, msg.sender, amount0);
        TransferHelper.safeTransfer(token1, msg.sender, amount1);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Burn(msg.sender, amount, amount0, amount1);
        emit Transfer(msg.sender, address(0), amount);
    }
    
    function safeBurn(uint256 amount) public returns (uint256 amount0, uint256 amount1) {
        require(amount != 0, "Index token amount is equal to zero.");
        require(_balances[msg.sender] >= amount, "Not enough index token.");
        (amount0, amount1) = getBurnAmount(amount);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 avaliableIndexAmount0;
        uint256 avaliableIndexAmount1;
        uint256 avaliableIndexAmount;
        uint256 balance0S;
        uint256 balance1S;
        
        if(balance0 < amount0) {
            (balance1S, avaliableIndexAmount0) = getAmountOut(amount0, true);
            avaliableIndexAmount = avaliableIndexAmount0;
        } else {
            avaliableIndexAmount0 = amount;
            balance0 = amount0;
        }
        
        if(balance1 < amount1) {
            (balance0S, avaliableIndexAmount1) = getAmountOut(amount1, true);
            avaliableIndexAmount = avaliableIndexAmount1;
        } else {
            avaliableIndexAmount1 = amount;
            balance1 = amount1;
        }
        
        if(avaliableIndexAmount0 != avaliableIndexAmount1 ) {
            if(avaliableIndexAmount0 > avaliableIndexAmount1) {
                avaliableIndexAmount = avaliableIndexAmount1;
                balance0 = balance0S;
            } else {
                avaliableIndexAmount = avaliableIndexAmount0;
                balance1 = balance1S;
            }
        }
        
        TransferHelper.safeTransfer(token0, msg.sender, balance0);
        TransferHelper.safeTransfer(token1, msg.sender, balance1);
        _balances[msg.sender] = _balances[msg.sender].sub(avaliableIndexAmount);
        _totalSupply = _totalSupply.sub(avaliableIndexAmount);
        emit Burn(msg.sender, avaliableIndexAmount, balance0, balance1);
        emit Transfer(msg.sender, address(0), avaliableIndexAmount);
    }
    
    function burnAndConvert(uint amount, address convertToken) public returns (uint amountConverted) {
        require(amount != 0, "Index token amount is equal to zero.");
        require(_balances[msg.sender] >= amount, "Not enough index token.");
        (uint256 amount0, uint256 amount1) = getBurnAmount(amount);
        address[] memory addresses = new address[](2);
        addresses[0] = token0;
        addresses[1] = convertToken;
        uint256[] memory amounts0 = router.swapExactTokensForTokens(amount0, 0, addresses, msg.sender, block.timestamp + 3600);
        addresses[0] = token1;
        uint256[] memory amounts1 = router.swapExactTokensForTokens(amount1, 0, addresses, msg.sender, block.timestamp + 3600);
        amountConverted = amounts0[1].add(amounts1[1]);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Burn(msg.sender, amount, amount0, amount1);
        emit Transfer(msg.sender, address(0), amount);
    }
    
    function getBurnAmount(uint amount) public view returns (uint amount0, uint amount1) {
        (uint256 amount0R, uint256 amount1R,) = pair.getReserves();
        amount0 = amount.div(Math.sqrt(amount1R.div(amount0R.mul(2))));
        amount1 = (amount0.div(2).mul(amount1R.div(amount0R)));
    }
    
    function getAmountOut(uint amount, bool isToken0) public view returns (uint counterTokenAmount, uint indexAmount) {
        (uint256 amount0R, uint256 amount1R,) = pair.getReserves();
        
        if(isToken0) {
            counterTokenAmount = (amount.div(2)).mul(amount1R).div(amount0R);
        } else {
            counterTokenAmount = (amount.mul(2)).mul(amount0R).div(amount1R);
        }
        
        indexAmount = Math.sqrt(SafeMath.mul(amount, counterTokenAmount));
    }
    
    function getAmountOutConvert(uint amount, address convertToken) public view returns (uint indexAmount) {
        uint256 amount0 = (amount.mul(2)).div(3);
        address[] memory addresses = new address[](2);
        addresses[1] = token0; 
        addresses[0] = convertToken; 
        uint256 amounts0 = router.getAmountsOut(amount0, addresses)[1];
        (, indexAmount) = getAmountOut(amounts0, true);
    }
    
    function getBurnAmountConvert(uint amount, address convertToken) public view returns (uint amountConverted) {
        (uint256 amount0, uint256 amount1) = getBurnAmount(amount);
        address[] memory addresses = new address[](2);
        addresses[0] = token0;
        addresses[1] = convertToken;
        amountConverted = router.getAmountsOut(amount0, addresses)[1];
        addresses[0] = token1;
        amountConverted = amountConverted.add(router.getAmountsOut(amount1, addresses)[1]);
    }
    
    function _mint(uint256 amount0, uint256 amount1) private returns (uint256 indexAmount) {
        require(amount0 != 0 && amount1 != 0, "Adjusted token amount is equal to zero.");
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1);

        uint256 amount = Math.sqrt(SafeMath.mul(amount0, amount1));
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        _totalSupply = _totalSupply.add(amount);
        emit Mint(msg.sender, amount, amount0, amount1);
        emit Transfer(address(0), msg.sender, amount);
        
        return amount;
    }
}