// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract SVTLottery is VRFV2WrapperConsumerBase, ConfirmedOwner {

    // Struct for storing generated random number
    struct RequestStatus {
        uint256 paid;
        bool fulfilled;
        uint256[] randomWords;
    }

    // Variables for generating random number
    uint32 private callbackGasLimit = 100000;
    uint8 private requestConfirmations = 3;
    uint8 private numWords = 1;

    // Percentage to be charged upon withdrawal of contribution
    uint8 public percentageCharge = 5;

    // Airdrop Threshhold
    uint32 public totalAirdropSent = 0;
    uint32 public totalAirdrop = 2000;

    // Reward Token variables
    uint16 public SLTRewardAmountTen = 1;
    uint16 public SLTRewardAmountHundred = 10;
    uint16 public SLTRewardAmountThousand = 50;
    uint16 public SLTRedemptionFee = 5;
    uint16 public SLTAirdropAmount = 50;
    uint16 public SLTPricePerRedemption = 1;
    uint16 public SLTPriceForWorthTen = 5;
    uint16 public SLTPriceForWorthHundred = 50;
    uint16 public SLTPriceForWorthThousand = 500;

    // Conversion Prices
    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;

    // Prices for each category
    uint16 public entryPriceForWorthTen = 1;
    uint16 public entryPriceForWorthHundred = 10;
    uint16 public entryPriceForWorthThousand = 100;

    // Potential Prize Amounts
    uint16 public WorthTenPotential = 10;
    uint16 public WorthHundredPotential = 100;
    uint16 public WorthThousandPotential = 1000;

    // Zero Value
    uint8 private zeroValue = 0;

    // Arrays for prizes
    uint256[] private worthTen = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0
    ];
    uint256[] private worthHundred = [
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 100, 1, 1, 1, 1, 1, 1, 1, 1
    ];
    uint256[] private worthThousand = [
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1000, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    ];

    //SLT Redemption Control
    bool isRedemptionActive = false;

    // address for airdrop tokens
    address public SLTAddress;

    // address WRAPPER
    address private wrapperAddress = 0x1D3bb92db7659F2062438791F131CFA396dfb592; // 0x5A861794B927983406fCE1D062e00b9368d97Df6
    //address private wrapperAddressETHSepolia = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46; // 0x5A861794B927983406fCE1D062e00b9368d97Df6
    //address public wrapperAddressArbitrumTestnet = 0x1D3bb92db7659F2062438791F131CFA396dfb592;
    //address public wrapperAddressArbitrumMainnet = 0x2D159AE3bFf04a10A355B608D22BDEC092e934fa;

    // Link Token Address
    address private linkTokenAddress = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E; // 0x514910771AF9Ca656af840dff83E8264EcF986CA
    //address private linkTokenAddressETHSepolia = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // 0x514910771AF9Ca656af840dff83E8264EcF986CA
    //address public linkTokenAddressArbitrumTestnet = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;
    //address public linkTokenAddressArbitrumMainnet = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    //address public priceFeedMainnet = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    //address public priceFeedzkEVMMainnet = 0x7C85dD6eBc1d318E909F22d51e756Cf066643341;
    //address public priceFeedzkEVMMainnetTestnet = 0xF8A652E8c9782C64fcF2F6459b619E8840baE817;
    //address public priceFeedArbitrumMainnet = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;
    //address public priceFeedArbitrumTestnet = 0xD1092a65338d049DB68D7Be6bD89d17a0929945e;
    //address private priceFeedSepolia = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address private priceFeedData = 0xD1092a65338d049DB68D7Be6bD89d17a0929945e;

    // Contributors List
    address[] public contributors;

    // Mapping for reentrancy guard to prevent recursive calls
    mapping (address => bool) private addressAccessLocked;

    // Mapping for Request ID to Random Number Stuct
    mapping (uint256 => RequestStatus) public s_requests;

    // Mapping for Address to Participation Status
    mapping (address => bool) private addressToParticipationStatus;

    // Mapping for Address to Airdrop claimed
    mapping (address => bool) public addressToAidropClaimed;

    // Mapping for address to Request ID
    mapping (address => uint256) public addressToRequestId;
    
    // Mapping to store the amount contributed by each address
    mapping (address => uint256) public addressToAmountContributed;
    mapping (address => uint256) public addressToTotalFundsAtTimeOfContribution;

    // Mapping for Address to Ability to participate
    mapping (address => uint256) private addressToDraw;

    // Chainlink price feed interface
    AggregatorV3Interface private priceFeed = AggregatorV3Interface(priceFeedData);

    // Link token interface
    LinkTokenInterface private link = LinkTokenInterface(linkTokenAddress);

    // Reward token interface
    IERC20 private SLT;

    // Modifier: Prevents reentrancy attacks
    modifier nonReentrant() {
        require(!addressAccessLocked[msg.sender], "Reentrancy guard: locked");
        addressAccessLocked[msg.sender] = true;
        _;
        addressAccessLocked[msg.sender] = false;
    }

    // Modifier: Require entry amount to be equal to or greater than entry price
    modifier addressLinkBalanceCheck(uint256 _amountRequired) {
        require(link.balanceOf(address(this)) >= _amountRequired, "Not enough Link in contract to enable this draw");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier transferAllowedLink(uint256 _amount) {
        require(link.allowance(msg.sender, address(this)) >= _amount, "Insufficient Link allowance");
        _;
    }

    //Modifier: Require redemption to be active
    modifier sltRedemptionActive() {
        require(isRedemptionActive, "Redemption Currently not Available");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier transferAllowedSLT(uint256 _amount) {
        require(SLT.allowance(msg.sender, address(this)) >= _amount, "Insufficient SLT allowance");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier totalAirdropSentCheck() {
        require(totalAirdropSent < totalAirdrop, "Airdrop Not Available Currently");
        _;
        totalAirdropSent += SLTAirdropAmount;
    }

    // Modifier: Check if withdrawal is possible
    modifier withdrawalPossible() {
        require(link.balanceOf(address(this)) > addressToTotalFundsAtTimeOfContribution[msg.sender], "You are not eligible to withdraw");
        _;
    }

    // Modifier: Check if withdrawal is possible
    modifier airdropClaimed() {
        require(!addressToAidropClaimed[msg.sender], "You have already claimed an airdrop");
        _;
        addressToAidropClaimed[msg.sender] = true;
    }

    // Modifier: Require sender to have more than the required redemption amount of SLT tokens
    modifier verifySLTRedemptionAmount() {
        require(SLT.balanceOf(msg.sender) >= SLTRedemptionFee, "Insufficient SLT balance");
        _;
    }

    // Modifier: Requires the contributor to exist (have contributed ETH)
    modifier contributorExists() {
        require(addressToAmountContributed[msg.sender] > zeroValue, "Contributor currently does not have any funds within the contract");
        _;
    }

    // Modifier: Requires the contributor to not exist
    modifier contributorDoesNotExist() {
        require(addressToAmountContributed[msg.sender] == zeroValue, "Contributor already exists");
        _;
    }

    // Modifier: Range check for contributors list index
    modifier participationCheck() {
        require(addressToParticipationStatus[msg.sender] == true, "Not a participant. Choose a draw");
        _;
        addressToParticipationStatus[msg.sender] == false;
    }

    // Modifier: Require random number to be available
    modifier randomNumberAvailable() {
        uint256 _requestId = addressToRequestId[msg.sender];
        require(s_requests[_requestId].fulfilled == true, "Random Number not yet Generated");
        _;
    }

    // Modifier: Check amount of SLT tokens in contract
    modifier SLTAmountCheck() {
        require(SLT.balanceOf(address(this)) > zeroValue, "Not enough SLT tokens in contract");
        _;
    }

    constructor()
    ConfirmedOwner(msg.sender)
    VRFV2WrapperConsumerBase(linkTokenAddress, wrapperAddress) 
    {}

    // Function: Get the current ETH price from the Chainlink price feed
    function checkLinkPrice()
        internal
        view
        returns(uint256)
    {
        (,int256 price,,,) = priceFeed.latestRoundData();
        uint256 LinkPrice = uint256(price) * tenTen * 10;
        return LinkPrice;
    }

    // Function: Convert dollar to ETH equivalent
    function convertDollarToLink(uint256 dollarAmount)
        internal
        view
        returns(uint256) 
    {
        uint256 currentLinkPrice = checkLinkPrice();
        uint256 LinkEquivalent = ((dollarAmount * tenEighteen) / (currentLinkPrice / tenTen)) * tenEight;
        return LinkEquivalent;
    }

    // Function: Allow contributors to contribute ETH to the smart contract
        function contribute(uint256 _linkTokenAmount)
        external 
        nonReentrant
        contributorDoesNotExist
        transferAllowedLink(_linkTokenAmount)
    {
        link.transferFrom(msg.sender, address(this), _linkTokenAmount);
        addressToTotalFundsAtTimeOfContribution[msg.sender] = link.balanceOf(address(this)) - _linkTokenAmount;
        addressToAmountContributed[msg.sender] = _linkTokenAmount;
        contributors.push(msg.sender);
    }

    //Function: Get the amount a contributor has contributed
    function getWithdrawalAmount()
        public
        view
        contributorExists
        withdrawalPossible
        returns(uint256 contributionLinkTokenAmountAfterCharge, uint256 indexOfContributor)
    {
        uint256 totalFunds = link.balanceOf(address(this));
        uint256 contributorWeight;
        uint256 currentContributorWeight;
        uint256 amountContributed;
        uint256 contributorAmount;
        uint256 totalFundsAtTimeOfContribution;
        uint256 totalWeight = 0;
        uint256 amountToWithdraw;
        uint256 contributionCharge;
        for(uint256 index = 0; index < contributors.length; index++) {
            amountContributed = addressToAmountContributed[contributors[index]];
            totalFundsAtTimeOfContribution = addressToTotalFundsAtTimeOfContribution[contributors[index]];
            currentContributorWeight = amountContributed * (totalFunds - totalFundsAtTimeOfContribution);
            totalWeight += currentContributorWeight;
            if(msg.sender == contributors[index]) {
                contributorWeight = currentContributorWeight;
                contributorAmount = amountContributed;
                indexOfContributor = index;
            }
        }
        amountToWithdraw = (((contributorWeight * tenEight) / totalWeight) * totalFunds) / tenEight;
        if(amountToWithdraw > contributorAmount){
            contributionCharge = (percentageCharge * (amountToWithdraw - contributorAmount)) / hundredPercent;
        }
        else{
            contributionCharge = 0;
        }
        contributionLinkTokenAmountAfterCharge = amountToWithdraw - contributionCharge;
        return (contributionLinkTokenAmountAfterCharge, indexOfContributor);
    }

    // Function: Allow contributors to withdraw their contributed ETH
    function withdrawContribution()
        external
        nonReentrant
    {
        (uint256 contributionLinkTokenAmountAfterCharge, uint256 indexOfContributor) = getWithdrawalAmount();
        if(contributionLinkTokenAmountAfterCharge > 0) {
            contributors[indexOfContributor] = contributors[contributors.length - 1];
            contributors.pop();
            addressToAmountContributed[msg.sender] = zeroValue;
            addressToTotalFundsAtTimeOfContribution[msg.sender] = zeroValue;
        }
        link.transfer(msg.sender, contributionLinkTokenAmountAfterCharge);
    }

    //Function: Set the percentage to be charged by the contract upon withdrawal
    function updatePercentage(uint8 _percentage)
        external 
        onlyOwner
    {
        percentageCharge = _percentage;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForTen(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthTen = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForHundred(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthHundred = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForThousand(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthThousand = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForTenSLT(uint16 _newPrice)
        external
        onlyOwner
    {
        SLTPriceForWorthTen = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForHundredSLT(uint16 _newPrice)
        external
        onlyOwner
    {
        SLTPriceForWorthHundred = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForThousandSLT(uint16 _newPrice)
        external
        onlyOwner
    {
        SLTPriceForWorthThousand = _newPrice;
    }

    // Function: Participate to win potentially 10 Link
    function playLotteryWorthTen()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthTenPotential))
        transferAllowedLink(convertDollarToLink(entryPriceForWorthTen))
    {
        uint256 entryFee = convertDollarToLink(entryPriceForWorthTen);
        link.transferFrom(msg.sender, address(this), entryFee);
        rewardSLT(msg.sender, SLTRewardAmountTen);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthTenPotential;
    }

    // Function: Participate to win potentially 70 Link
    function playLotteryWorthHundred()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthHundredPotential))
        transferAllowedLink(convertDollarToLink(entryPriceForWorthHundred))
    {
        uint256 entryFee = convertDollarToLink(entryPriceForWorthHundred);
        link.transferFrom(msg.sender, address(this), entryFee);
        rewardSLT(msg.sender, SLTRewardAmountHundred);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthHundredPotential;
    }

    // Function: Participate to win potentially 700 Link
    function playLotteryWorthThousand()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthThousandPotential))
        transferAllowedLink(convertDollarToLink(entryPriceForWorthThousand))
    {
        uint256 entryFee = convertDollarToLink(entryPriceForWorthThousand);
        link.transferFrom(msg.sender, address(this), entryFee);
        rewardSLT(msg.sender, SLTRewardAmountThousand);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthThousandPotential;
    }

    // Function: Participate to win potentially 10 Link
    function playLotteryWorthTenSLT()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthTenPotential))
        transferAllowedSLT(SLTPriceForWorthTen * tenEighteen)
    {
        SLT.transferFrom(msg.sender, address(this), SLTPriceForWorthTen * tenEighteen);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthTenPotential;
    }

    // Function: Participate to win potentially 70 Link
    function playLotteryWorthHundredSLT()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthHundredPotential))
        transferAllowedSLT(SLTPriceForWorthHundred * tenEighteen)
    {
        SLT.transferFrom(msg.sender, address(this), SLTPriceForWorthHundred * tenEighteen);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthHundredPotential;
    }

    // Function: Participate to win potentially 700 Link
    function playLotteryWorthThousandSLT()
        external
        addressLinkBalanceCheck(convertDollarToLink(WorthThousandPotential))
        transferAllowedSLT(SLTPriceForWorthThousand * tenEighteen)
    {
        SLT.transferFrom(msg.sender, address(this), SLTPriceForWorthThousand * tenEighteen);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToDraw[msg.sender] = WorthThousandPotential;
    }

    // Function: Get random number
    function requestRandomWords()
        private
        returns(uint256 requestId)
    {
        requestId = requestRandomness(callbackGasLimit, requestConfirmations, numWords);
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        return requestId;
    }

    // Function: Receive random number
    function fulfillRandomWords( uint256 _requestId, uint256[] memory _randomWords)
        internal
        override
    {
        require(s_requests[_requestId].paid > zeroValue, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
    }

    // Function: Get draw results
    function getFinalResultValue()
        public
        view
        participationCheck
        randomNumberAvailable
        returns(uint256 LinkAmountWon)
    {
        uint256 LinkAmountToSend = zeroValue;
        uint256 randomNumber = zeroValue;
        uint256 requestId = addressToRequestId[msg.sender];
        uint256 realRandomNumber = getRandomNumber(requestId);
        uint256 drawAmount = addressToDraw[msg.sender];
        if(drawAmount == WorthTenPotential){
            randomNumber = realRandomNumber % worthTen.length;
            LinkAmountToSend = convertDollarToLink(worthTen[randomNumber]);
        } else if(drawAmount == WorthHundredPotential){
            randomNumber = realRandomNumber % worthHundred.length;
            LinkAmountToSend = convertDollarToLink(worthHundred[randomNumber]);
        } else if(drawAmount == WorthThousandPotential){
            randomNumber = realRandomNumber % worthThousand.length;
            LinkAmountToSend = convertDollarToLink(worthThousand[randomNumber]);
        }
        LinkAmountWon = LinkAmountToSend;
        return LinkAmountWon;
    }

    // Function: Get draw results
    function getFinalResult()
        public
    {
        uint256 LinkAmountToSend = getFinalResultValue();
        link.transfer(msg.sender, LinkAmountToSend);
        addressToDraw[msg.sender] = zeroValue;
    }


    // Function: Get random number for final result
    function getRandomNumber(uint256 _requestId)
        public
        view
        returns(uint256)
    {
        RequestStatus memory request = s_requests[_requestId];
        return (request.randomWords[0]);
    }

    // Function: Send SLT as airdrop
    function claimAirdropSLT()
        external
        airdropClaimed
        totalAirdropSentCheck
    {
        SLT.transfer(msg.sender, SLTAirdropAmount * tenEighteen);
    }

    // Function: Send SLT as reward
    function rewardSLT(address _recipientAddress, uint16 _SLTRewardAmount)
        private
        SLTAmountCheck
    {
        SLT.transfer(_recipientAddress, _SLTRewardAmount * tenEighteen);
    }

    // FUnction: Redeem SLT
    function redeemSLT(uint16 _SLTRedemptionAmount)
        external
        transferAllowedSLT(_SLTRedemptionAmount * tenEighteen)
        verifySLTRedemptionAmount
        sltRedemptionActive
    {
        
        SLT.transferFrom(msg.sender, address(this), _SLTRedemptionAmount * tenEighteen);
        uint256 LinkAmountToSend = convertDollarToLink((((_SLTRedemptionAmount * tenEight) / SLTRedemptionFee) * SLTPricePerRedemption) / tenEight);
        link.transfer(msg.sender, LinkAmountToSend);
    }
    
    // Function: Set Reward Token Address
    function updateSLTAddress(address _SLTAddress)
        external
        onlyOwner
    {
        SLTAddress = _SLTAddress;
        SLT = IERC20(SLTAddress);
    }

    // Function: Update reward token worth
    function updateSLTPricePerRedemption(uint16 _SLTPricePerRedemption)
        external
        onlyOwner
    {
        SLTPricePerRedemption = _SLTPricePerRedemption;
    }

    // Function: Update reward token redemption price
    function updateSLTRedemptionFee(uint16 _SLTRedemptionFee)
        external
        onlyOwner
    {
        SLTRedemptionFee = _SLTRedemptionFee;
    }
    
    // Function: Update reward token redemption price
    function updateSLTAirdropLimit(uint16 _SLTAirdropLimit)
        external
        onlyOwner
    {
        totalAirdrop = _SLTAirdropLimit;
    }

    // Function: Update Airdrop Token Amount
    function updateSLTAirdropAmount(uint16 _newTokenAmount)
        external
        onlyOwner
    {
        SLTAirdropAmount = _newTokenAmount;
    }

    function updateSLTRewardForWorthTen(uint16 _newRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountTen = _newRewardAmount;
    }

    function updateSLTRewardForWorthHundred(uint16 _newRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountHundred = _newRewardAmount;
    }

    function updateSLTRewardForWorthThousand(uint16 _newRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountThousand = _newRewardAmount;
    }
    
    // Function: Update Airdrop Token Amount
    function activateDeactivateSLTRedemption(bool status)
        external
        onlyOwner
    {
        isRedemptionActive = status;
    }
}