
var TestRPC = require("ethereumjs-testrpc");
var solc = require('solc');
var fs = require('fs');
var Web3 = require('web3');
var web3 = new Web3();

var input = { 'zippertoken.sol' : fs.readFileSync('zippertoken.sol', 'utf8') };
var output = solc.compile({sources: input}, 1);

process.removeAllListeners("uncaughtException");

var logger = {
  log: function(message) {
//     console.log(message);
  }
};

var port = 8546;

function testToken(account, account2, token)
{
    token.name(function(err, result) { console.log("Name is " + result) });
    token.symbol(function(err, result) { console.log("Symbol is " + result) });
    token.decimals(function(err, result) { console.log("Symbol is " + result) });
    token.allEvents().watch(function(error, event) {
       if (!error)
          console.log(event);
    });
    
    token.issue(10000, { from: account }, function(err, result) { 
        if (err) { console.log(err); } 
        if (result) {
           token.totalSupply(function(err, result) {
               console.log("Total supply after issue " + result);
           });
           token.balanceOf(account, function(err, result) { 
             console.log("Balance after issue is " + result);
             token.redeem(5000, { from: account }, function(err, result) {
                token.totalSupply(function(err, result) {
                   console.log("Total supply after issue " + result);
                });

                token.balanceOf(account, function(err, result) { 
                  console.log("Balance after issue redeem " + result);
                  
                  token.transfer(account2, 500, { from: account }, function(err, result) { 
                       token.balanceOf(account, function(err, result) {
                           console.log("Balance account1 after transfer " + result);
                           token.balanceOf(account2, function(err, result) {
                               console.log("Balance account2 after transfer " + result);
                           });
                       });
                  });
                });
             });
           });
        } 
    });
}

server = TestRPC.server({ logger: logger /*, debug: true, verbose: true */ });
server.listen(port, function(err, state) {
     if (err)
     {
        console.log(err);
        return;
     } 

     web3.setProvider(new Web3.providers.HttpProvider("http://localhost:" + port));

     web3.eth.getAccounts(function(err, result) {
        var account = result[0];
        var account2 = result[1];    
  
        var StandardZipperTokenFunctionality = web3.eth.contract(JSON.parse(output.contracts["StandardZipperTokenFunctionality"].interface));
        var standardZTF = StandardZipperTokenFunctionality.new({ from: account, gas: 1000000, data: "0x" + output.contracts["StandardZipperTokenFunctionality"].bytecode },
          function(err, result) {
             if (err) { console.log(err); return; }
             if (standardZTF.address)
             {
                 console.log("StandardZTF at " + standardZTF.address);
                 
                 var ITokenActionValidator = web3.eth.contract(JSON.parse(output.contracts["ITokenActionValidator"].interface));
                 var itokenactionvalidator = ITokenActionValidator.new({ from: account, gas: 1000000, data: "0x" + 
                    output.contracts["ITokenActionValidator"].bytecode }, function(err, result) {
                           if (err) { console.log(err); return; }
                           if (itokenactionvalidator.address)
                           { 
                               console.log("ITokenActionValidator at " + itokenactionvalidator.address);
                               console.log("Linking bytecode for PZipToken..");
                  
                               var pzipbytecode = solc.linkBytecode(output.contracts["PZipToken"].bytecode, { "StandardZipperTokenFunctionality" : standardZTF.address });
                 
                               var PZipToken = web3.eth.contract(JSON.parse(output.contracts["PZipToken"].interface));
                               var pziptoken = PZipToken.new(account, itokenactionvalidator.address, "0xf8260e2729e5f618005dc011a36d699bd2e53055",
                                   { from: account, gas: 1000000, data: "0x" + pzipbytecode }, function(err, result) {
                                        if (err) { console.log(err); return; }
                                        if (pziptoken.address)
                                        {
                                           console.log("PZipToken at " + pziptoken.address);
                                           
                                           testToken(account, account2, pziptoken);
                                        }
                               });
                           }
                 });
             }
          });
      });
});

