// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract SVTLotteryPresale is ConfirmedOwner {
    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;
    string public dollarAmountOfSLT = "1 SLT = $0.02 for Presale";

    address public SLTAddress = 0x42B5bcE9095aeC6E605991cA6dE23330C43b124D;
    IERC20 private SLT = IERC20(SLTAddress);    

    address private priceFeedData = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    AggregatorV3Interface private priceFeed = AggregatorV3Interface(priceFeedData);

    modifier sufficientTokensInContract(uint256 _amountRequired) {
        require(SLT.balanceOf(address(this)) >= _amountRequired, "Not enough SLT in contract");
        _;
    }

    constructor()
    ConfirmedOwner(msg.sender)
    {}

    function checkETHPrice()
        public
        view
        returns(uint256)
    {
        (,int256 price,,,) = priceFeed.latestRoundData();
        uint256 ETHPrice = uint256(price) * tenTen;
        return ETHPrice;
    }

    function convertEthToDollar(uint256 ethAmountInWei) 
    public 
    view 
    returns (uint256) 
    {
        uint256 currentEthPrice = checkETHPrice();
        uint256 dollarEquivalent = (ethAmountInWei * currentEthPrice) / 10**18;
        return dollarEquivalent;
    }

    function convertDollarToETH(uint256 dollarAmount)
        public
        view
        returns(uint256) 
    {
        uint256 currentETHPrice = checkETHPrice();
        uint256 ETHEquivalent = ((dollarAmount * tenEighteen) / (currentETHPrice / tenTen)) * tenEight;
        return ETHEquivalent;
    }

    function withdraw() 
    public 
    onlyOwner
    {
        payable(msg.sender).transfer(address(this).balance);
        SLT.transfer(msg.sender, SLT.balanceOf(address(this)));
    }

    // Function: Allow participants to buy tokens for $1
    function buyToken() 
    public 
    payable
    sufficientTokensInContract(((dollarEquiv / ((2 * tenEight)/100)) * tenEight))
    returns(uint256 SLTtoSend, uint256 dollarEquiv)
    {
        dollarEquiv = convertEthToDollar(msg.value);
        SLTtoSend = (dollarEquiv / ((2 * tenEight)/100)) * tenEight;
        SLT.transfer(msg.sender, SLTtoSend);
        return (SLTtoSend, dollarEquiv);
    }
}