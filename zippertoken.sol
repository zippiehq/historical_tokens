pragma solidity ^0.4.4;

/* Based on zeppelin-solidity */
contract IAuthedForwarder
{
    function whitelist(bytes4 sig);
}

/*
 * ERC20 interface
 * see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 { /* interface */
  function totalSupply() constant returns (uint);
  function balanceOf(address who) constant returns (uint);
  function allowance(address owner, address spender) constant returns (uint);

  function transfer(address to, uint value) returns (bool ok);
  function transferFrom(address from, address to, uint value) returns (bool ok);
  function approve(address spender, uint value) returns (bool ok);

  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
}

contract Zipper_ERC20 is ERC20 {
  function name() constant returns (string result);
  function symbol() constant returns (string result);
  function decimals() constant returns (uint result);

  function transferAuthed(address caller, address to, uint value) returns (bool ok);
  function transferFromAuthed(address caller, address from, address to, uint value) returns (bool ok);
  function approveAuthed(address caller, address spender, uint value) returns (bool ok);
}


/**
 * Math operations with safety checks
 */
library SafeMath {
  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) throw;
  }
}

/**
 * Interface that the token calls to check for if a transaction can go through and at what fee
*/

contract ITokenActionValidator
{
    function transferOK(address _caller, address _to, uint _value) returns (bool success, uint fee, address feeReceiver)
    {
        return (true, 0, this);
    }

    function transferFromOK(address _caller, address _from, address _to, uint _value) returns  (bool success, uint fee, address feeReceiver)
    {
        return (true, 0, this);
    }

    function approveOK(address _caller, address _spender, uint _value) returns (bool success)
    {
        return true;
    }

    function getAuthedForwarder() constant returns (address forwarder)
    {
        return this;
    }

    function setAuthDataOK(address _caller, ITokenActionValidator _validator, IAuthedForwarder _authedForwarder) returns (bool success)
    {
        return true;
    }
}

/**
 * Basic functionality of the token is divided out into a library to limit token size
 */
library StandardZipperTokenFunctionality
{
  struct data {
      mapping(address => uint) balances;
      mapping (address => mapping (address => uint)) allowed;
      uint totalSupply;
      ITokenActionValidator validator;
      IAuthedForwarder authedForwarder;
  }

  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);

  function transfer(data storage self, address _caller, address _to, uint _value) returns (bool success) {
    var (tOK, fee, feeReceiver) = self.validator.transferOK(_caller, _to, _value);

    if (!tOK)
        return false;

    var valueplusfee = SafeMath.safeAdd(_value, fee);

    self.balances[_caller] = SafeMath.safeSub(self.balances[_caller], valueplusfee);
    self.balances[_to] = SafeMath.safeAdd(self.balances[_to], _value);
    Transfer(msg.sender, _to, _value);

    if (fee > 0)
    {
        self.balances[feeReceiver] = SafeMath.safeAdd(self.balances[feeReceiver], fee);
        Transfer(msg.sender, feeReceiver, fee);
    }
    return true;
  }

  function transferFrom(data storage self, address _caller, address _from, address _to, uint _value) returns (bool success) {
    var (tOK, fee, feeReceiver) = self.validator.transferFromOK(_caller, _from, _to, _value);

    if (!tOK)
        return false;

    var _allowance = self.allowed[_from][_caller];

    // This is technically done in safeSub below but it's prettier to not throw.
    if (_value >= _allowance)
        return false;

    self.balances[_to] = SafeMath.safeAdd(self.balances[_to], _value);
    self.balances[_from] = SafeMath.safeSub(self.balances[_from], _value);
    self.allowed[_from][_caller] = SafeMath.safeSub(_allowance, _value);
    Transfer(_from, _to, _value);
    return true;
  }

  function approve(data storage self, address _caller, address _spender, uint _value) returns (bool success) {
    if (!self.validator.approveOK(_caller, _spender, _value))
        return false;
    self.allowed[_caller][_spender] = _value;
    Approval(_caller, _spender, _value);
    return true;
  }

  function setAuthData(data storage self, ITokenActionValidator _newvalidator, IAuthedForwarder _authedForwarder) returns (bool success)
  {
    if (!self.validator.setAuthDataOK(msg.sender, _newvalidator, _authedForwarder))
        return false;
    self.validator = _newvalidator;
    self.authedForwarder = _authedForwarder;
    self.authedForwarder.whitelist(bytes4(bytes32(sha3("transferAuthed(address,address,uint256)"))));
    self.authedForwarder.whitelist(bytes4(bytes32(sha3("transferFromAuthed(address,address,address,uint256)"))));
    self.authedForwarder.whitelist(bytes4(bytes32(sha3("approveAuthed(address,address,uint256)"))));
    return true;
  }
}

contract StandardZipperToken is Zipper_ERC20 {
  StandardZipperTokenFunctionality.data internal data;

  function StandardZipperToken(ITokenActionValidator _validator, IAuthedForwarder _authedForwarder)
  {
    data.validator = _validator;
    data.authedForwarder = _authedForwarder;
    data.authedForwarder.whitelist(bytes4(bytes32(sha3("transferAuthed(address,address,uint256)"))));
    data.authedForwarder.whitelist(bytes4(bytes32(sha3("transferFromAuthed(address,address,address,uint256)"))));
    data.authedForwarder.whitelist(bytes4(bytes32(sha3("approveAuthed(address,address,uint256)"))));
  }

  function totalSupply() constant returns (uint)
  {
    return data.totalSupply;
  }

  function balanceOf(address _who) constant returns (uint)
  {
    return data.balances[_who];
  }

  function allowance(address _owner, address _spender) constant returns (uint)
  {
    return data.allowed[_owner][_spender];
  }

  function transfer(address to, uint value) returns (bool ok)
  {
    return StandardZipperTokenFunctionality.transfer(data, msg.sender, to, value);
  }
  function transferFrom(address from, address to, uint value) returns (bool ok)
  {
    return StandardZipperTokenFunctionality.transferFrom(data, msg.sender, from, to, value);
  }

  function approve(address spender, uint value) returns (bool ok)
  {
    return StandardZipperTokenFunctionality.approve(data, msg.sender, spender, value);
  }

  function transferAuthed(address caller, address to, uint value) returns (bool ok)
  {
    if (msg.sender != address(data.authedForwarder))
      return false;

    return StandardZipperTokenFunctionality.transfer(data, caller, to, value);
  }

  function transferFromAuthed(address caller, address from, address to, uint value) returns (bool ok)
  {
    if (msg.sender != address(data.authedForwarder))
       return false;

    return StandardZipperTokenFunctionality.transferFrom(data, caller, from, to, value);
  }

  function approveAuthed(address caller, address spender, uint value) returns (bool ok)
  {
    if (msg.sender != address(data.authedForwarder))
        return false;

    return StandardZipperTokenFunctionality.approve(data, caller, spender, value);
  }

  /* maintainence */
  function setAuthData(ITokenActionValidator _newvalidator, IAuthedForwarder _authedForwarder) returns (bool success)
  {
    return StandardZipperTokenFunctionality.setAuthData(data, _newvalidator, _authedForwarder);
  }
}

/**
 * A simple issuer token
 */

contract SimpleIssuerToken is StandardZipperToken
{
    address issuer;

    function SimpleIssuerToken(address _issuer, ITokenActionValidator _validator, IAuthedForwarder _authedForwarder)
        StandardZipperToken(_validator, _authedForwarder)
    {
        issuer = _issuer;
    }

    function issue(uint _amount) returns (bool success)
    {
        if (msg.sender != issuer)
            return false;
        data.balances[msg.sender] = SafeMath.safeAdd(data.balances[msg.sender], _amount);
        data.totalSupply = SafeMath.safeAdd(data.totalSupply, _amount);
        Transfer(this, msg.sender, _amount);
        return true;
    }

    function redeem(uint _amount) returns (bool success)
    {
        if (msg.sender != issuer)
            return false;
        data.balances[msg.sender] = SafeMath.safeSub(data.balances[msg.sender], _amount);
        data.totalSupply = SafeMath.safeSub(data.totalSupply, _amount);
        Transfer(msg.sender, this, _amount);
        return true;
    }

    function setIssuer(address _issuer) returns (bool success)
    {
        if (msg.sender != issuer)
            return false;
        issuer = _issuer;
        return true;
    }
}

/**
 * The provisional ZIP token
*/

contract PZipToken is SimpleIssuerToken
{
    function PZipToken(address _issuer, ITokenActionValidator _validator, IAuthedForwarder _authedForwarder)
         SimpleIssuerToken(_issuer, _validator, _authedForwarder)
    {
    }

   function name() constant returns (string result) { return "PZipToken"; }
   function symbol() constant returns (string result) { return "PZIP"; }
   function decimals() constant returns (uint result) { return 5; }
}
