const { ethers } = require("hardhat")
const { expect } = require("chai")
const { time } = require("./utilities")

describe("AnnexBoostFarm", function() {
  before(async function() {
    this.signers = await ethers.getSigners()
    this.annOwner = this.signers[0]
    this.alice = this.signers[1]
    this.bob = this.signers[2]
    this.carol = this.signers[3]
    this.dev = this.signers[4]
    this.minter = this.signers[5]
    this.vaulter = this.signers[6]

    this.AnnexBoostFarm = await ethers.getContractFactory("AnnexBoostFarm")
    this.BoostToken = await ethers.getContractFactory("AgencyWolfBillionaireClub")
    this.ANNToken = await ethers.getContractFactory("ANN")
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
  })

  beforeEach(async function() {
    this.annex = await this.ANNToken.deploy(this.annOwner.address)
    await this.annex.deployed()
    this.boostToken = await this.BoostToken.deploy(
      "AgencyWolfBillionaireClub",
      "AWBC",
      "https://nftassets.annex.finance/ipfs/QmeHoeon52U4HYuemkfuKtzxcSZV2xSW69rBeEKKPzav4G",
      this.annex.address
    )
    await this.boostToken.deployed()
    // console.log("ann owner: ", await this.annex.owner())
    // console.log("signers: ", this.signers)
    // this.signers.map((sign) => console.log(sign.address))
  })

  it("should set correct state variables", async function() {
    this.chef = await this.AnnexBoostFarm.deploy(
      this.annex.address,
      this.boostToken.address,
      this.dev.address,
      "1000",
      "1000",
      "0",
      "1000"
    )
    await this.chef.deployed()

    // await this.annex.authorizeOwnershipTransfer(this.chef.address)

    const annex = await this.chef.annex()
    const boostToken = await this.chef.boostFactor()
    const devaddr = await this.chef.devaddr()
    const owner = await this.annex.owner()

    expect(annex).to.equal(this.annex.address)
    expect(boostToken).to.equal(this.boostToken.address)
    expect(devaddr).to.equal(this.dev.address)
    expect(owner).to.equal(this.annOwner.address)
  })

  it("should allow dev and only dev to update dev", async function() {
    this.chef = await this.AnnexBoostFarm.deploy(
      this.annex.address,
      this.boostToken.address,
      this.dev.address,
      "1000",
      "1000",
      "0",
      "1000"
    )
    await this.chef.deployed()

    expect(await this.chef.devaddr()).to.equal(this.dev.address)

    await expect(this.chef.connect(this.bob).dev(this.bob.address, { from: this.bob.address })).to.be.revertedWith("dev: wut?")

    await this.chef.connect(this.dev).dev(this.bob.address, { from: this.dev.address })

    expect(await this.chef.devaddr()).to.equal(this.bob.address)

    await this.chef.connect(this.bob).dev(this.alice.address, { from: this.bob.address })

    expect(await this.chef.devaddr()).to.equal(this.alice.address)
  })

  context("With ERC/LP token added to the field", function() {
    beforeEach(async function() {
      this.lp = await this.ERC20Mock.deploy("LPToken", "LP", "10000000000")

      await this.lp.transfer(this.alice.address, "1000")

      await this.lp.transfer(this.bob.address, "1000")

      await this.lp.transfer(this.carol.address, "1000")

      this.lp2 = await this.ERC20Mock.deploy("LPToken2", "LP2", "10000000000")

      await this.lp2.transfer(this.alice.address, "1000")

      await this.lp2.transfer(this.bob.address, "1000")

      await this.lp2.transfer(this.carol.address, "1000")

      await this.annex.transfer(this.vaulter.address, "1000")
    })

    it("should allow emergency withdraw", async function() {
      // 100 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "100",
        "1000"
      )
      await this.chef.deployed()

      await this.chef.add("100", this.lp.address, true)

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })

      await this.chef.connect(this.bob).deposit(0, "100", { from: this.bob.address })

      expect(await this.lp.balanceOf(this.bob.address)).to.equal("900")

      await this.chef.connect(this.bob).emergencyWithdraw(0, { from: this.bob.address })

      expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
    })

    it("should give out ANNs only after farming time", async function() {
      // 100 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "100",
        "1000"
      )
      await this.chef.deployed()

      this.annex.transfer(this.chef.address, "10000")

      // await this.annex.transferOwnership(this.chef.address)

      await this.chef.add("100", this.lp.address, true)
      expect(await this.chef.totalAllocPoint()).to.equal("100")

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await this.chef.connect(this.bob).deposit(0, 100, { from: this.bob.address })
      await time.advanceBlockTo("89")
      await this.chef.connect(this.bob).deposit(0, 0, { from: this.bob.address }) // block 90
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("0")
      await time.advanceBlockTo("94")

      await this.chef.connect(this.bob).deposit(0, 0, { from: this.bob.address }) // block 95
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("0")
      await time.advanceBlockTo("99")

      await this.chef.connect(this.bob).deposit(0, 0, { from: this.bob.address }) // block 100
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("0")
      await time.advanceBlockTo("100")

      await this.chef.connect(this.bob).deposit(0, 0, { from: this.bob.address }) // block 101
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("1000")

      await time.advanceBlockTo("104")
      await this.chef.connect(this.bob).deposit(0, "0", { from: this.bob.address }) // block 105

      expect(await this.annex.balanceOf(this.bob.address)).to.equal("5000")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("500")
      expect(await this.annex.totalSupply()).to.equal("1000000000000000000000000000")
    })

    it("should not distribute ANNs if no one deposit", async function() {
      // 100 per block farming rate starting at block 200 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "200",
        "1000"
      )
      await this.chef.deployed()

      this.annex.transfer(this.chef.address, "10000")

      // await this.annex.transferOwnership(this.chef.address)
      await this.chef.add("100", this.lp.address, true)
      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await time.advanceBlockTo("199")
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("10000")
      await time.advanceBlockTo("204")
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("10000")
      await time.advanceBlockTo("209")
      await this.chef.connect(this.bob).deposit(0, "10", { from: this.bob.address }) // block 210
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("10000")
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("0")
      expect(await this.lp.balanceOf(this.bob.address)).to.equal("990")
      await time.advanceBlockTo("219")
      await this.chef.connect(this.bob).withdraw(0, "10", { from: this.bob.address }) // block 220
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("9000")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("1000")
      expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
    })

    it("should distribute ANNs properly for each staker", async function() {
      // 100 per block farming rate starting at block 300 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "300",
        "1000"
      )
      await this.chef.deployed()

      // Transfer 10,000 ANN to AnnexBoostFarm
      this.annex.transfer(this.chef.address, "100000")

      // await this.annex.transferOwnership(this.chef.address)
      await this.chef.add("100", this.lp.address, true)
      await this.lp.connect(this.alice).approve(this.chef.address, "1000", {
        from: this.alice.address,
      })
      await this.lp.connect(this.bob).approve(this.chef.address, "1000", {
        from: this.bob.address,
      })
      await this.lp.connect(this.carol).approve(this.chef.address, "1000", {
        from: this.carol.address,
      })
      // Alice deposits 10 LPs at block 310
      await time.advanceBlockTo("309")
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      // Bob deposits 20 LPs at block 314
      await time.advanceBlockTo("313")
      await this.chef.connect(this.bob).deposit(0, "20", { from: this.bob.address })
      // Carol deposits 30 LPs at block 318
      await time.advanceBlockTo("317")
      await this.chef.connect(this.carol).deposit(0, "30", { from: this.carol.address })
      // Alice deposits 10 more LPs at block 320. At this point:
      //   Alice should have: 4*1000 + 4*1/3*1000 + 2*1/6*1000 = 5666
      //   AnnexBoostFarm should have the remaining: 10000 - 5666 = 4334
      await time.advanceBlockTo("319")
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("93334")
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("5666")
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.carol.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("93334")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("1000")
      // Bob withdraws 5 LPs at block 330. At this point:
      //   Bob should have: 4*2/3*1000 + 2*2/6*1000 + 10*2/7*1000 = 6190
      await time.advanceBlockTo("329")
      await this.chef.connect(this.bob).withdraw(0, "5", { from: this.bob.address })
      expect(await this.annex.totalSupply()).to.equal("1000000000000000000000000000")
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("5666")
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("6190")
      expect(await this.annex.balanceOf(this.carol.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("86144")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("2000")
      // Alice withdraws 20 LPs at block 340.
      // Bob withdraws 15 LPs at block 350.
      // Carol withdraws 30 LPs at block 360.
      await time.advanceBlockTo("339")
      await this.chef.connect(this.alice).withdraw(0, "20", { from: this.alice.address })
      await time.advanceBlockTo("349")
      await this.chef.connect(this.bob).withdraw(0, "15", { from: this.bob.address })
      await time.advanceBlockTo("359")
      await this.chef.connect(this.carol).withdraw(0, "30", { from: this.carol.address })
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("45001")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("5000")
      // // Alice should have: 5666 + 10*2/7*1000 + 10*2/6.5*1000 = 11600
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("11600")
      // // Bob should have: 6190 + 10*1.5/6.5 * 1000 + 10*1.5/4.5*1000 = 11831
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("11831")
      // // Carol should have: 2*3/6*1000 + 10*3/7*1000 + 10*3/6.5*1000 + 10*3/4.5*1000 + 10*1000 = 26568
      expect(await this.annex.balanceOf(this.carol.address)).to.equal("26568")
      // // All of them should have 1000 LPs back.
      expect(await this.lp.balanceOf(this.alice.address)).to.equal("1000")
      expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
      expect(await this.lp.balanceOf(this.carol.address)).to.equal("1000")
    })

    it("should give proper ANNs allocation to each pool", async function() {
      // 100 per block farming rate starting at block 400 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "400",
        "1000"
      )
      // await this.annex.transferOwnership(this.chef.address)
      await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
      await this.lp2.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      // Add first LP to the pool with allocation 1
      await this.chef.add("10", this.lp.address, true)
      // Alice deposits 10 LPs at block 410
      await time.advanceBlockTo("409")
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      // Add LP2 to the pool with allocation 2 at block 420
      await time.advanceBlockTo("419")
      await this.chef.add("20", this.lp2.address, true)
      // Alice should have 10*1000 pending reward
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("10000")
      // Bob deposits 10 LP2s at block 425
      await time.advanceBlockTo("424")
      await this.chef.connect(this.bob).deposit(1, "5", { from: this.bob.address })
      // Alice should have 10000 + 5*1/3*1000 = 11666 pending reward
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("11666")
      await time.advanceBlockTo("430")
      // At block 430. Bob should get 5*2/3*1000 = 3333. Alice should get ~1666 more.
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("13333")
      expect(await this.chef.pendingAnnex(1, this.bob.address)).to.equal("3333")
    })

    it("should stop giving bonus ANNs after the bonus period ends", async function() {
      // 100 per block farming rate starting at block 500 with bonus until block 600
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "500",
        "600"
      )

      // Transfer 10,000 ANN to AnnexBoostFarm
      this.annex.transfer(this.chef.address, "100000")

      // await this.annex.transferOwnership(this.chef.address)
      await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
      await this.chef.add("1", this.lp.address, true)
      // Alice deposits 10 LPs at block 590
      await time.advanceBlockTo("589")
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      // At block 605, she should have 1000*10 + 100*5 = 10500 pending.
      await time.advanceBlockTo("605")
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("10500")
      // At block 606, Alice withdraws all pending rewards and should get 10600.
      await this.chef.connect(this.alice).deposit(0, "0", { from: this.alice.address })
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("0")
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("10600")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("1060")
    })

    it("should give out ANNs only ANN single vault after farming time", async function() {
      // 100 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "700",
        "1000"
      )
      await this.chef.deployed()
      this.annex.transfer(this.chef.address, "20000")

      // await this.annex.transferOwnership(this.chef.address)

      await this.chef.add("100", this.annex.address, true)

      await this.annex.connect(this.vaulter).approve(this.chef.address, "1000", { from: this.vaulter.address })
      await this.chef.connect(this.vaulter).deposit(0, "100", { from: this.vaulter.address })
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("20100")
      await time.advanceBlockTo("689")

      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address }) // block 690
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("900")
      await time.advanceBlockTo("694")

      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address }) // block 695
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("900")
      await time.advanceBlockTo("699")

      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address }) // block 700
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("900")
      await time.advanceBlockTo("700")

      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address }) // block 701
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("1900")

      await this.chef.connect(this.vaulter).withdraw(0, "100", { from: this.vaulter.address }) // block 701
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("3000")
      await time.advanceBlockTo("704")
      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address }) // block 705

      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("3000")
      expect(await this.annex.balanceOf(this.dev.address)).to.equal("200")
      expect(await this.annex.balanceOf(this.chef.address)).to.equal("17800")

      // Vaulter deposit 100 LP
      await this.chef.connect(this.vaulter).deposit(0, "100", { from: this.vaulter.address })
      await time.advanceBlockTo("707")
      expect(await this.chef.pendingAnnex(0, this.vaulter.address)).to.equal("1000")
      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("2900")

      await this.chef.setAnnexPerBlock("200")
      await this.chef.updatePool(0)
      await time.advanceBlockTo("709")

      expect(await this.annex.balanceOf(this.chef.address)).to.equal("17300")
      expect((await this.chef.getPoolInfo(0)).lpSupply).to.equal("100")

      await this.chef.connect(this.vaulter).deposit(0, "0", { from: this.vaulter.address })

      expect(await this.annex.balanceOf(this.vaulter.address)).to.equal("10900")

      expect(await this.annex.totalSupply()).to.equal("1000000000000000000000000000")
    })

    // Boosting test
    it("should deposit lp before boosting", async function () {
      // 100 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "100",
        "100",
        "100",
        "1000"
      )
      await this.chef.deployed()

      await this.chef.add("100", this.lp.address, true)
      expect(await this.chef.totalAllocPoint()).to.equal("100")

      await this.boostToken.gift(1, this.bob.address)
      await this.boostToken.setStakingAddress(this.chef.address)
      await this.boostToken.connect(this.bob).approve(this.chef.address, 1, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("1")

      await expect(this.chef.connect(this.bob).boost(0, 1, { from: this.bob.address })).to.be.revertedWith("No deposited lptokens")

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await this.chef.connect(this.bob).deposit(0, "10", { from: this.bob.address })
      await this.chef.connect(this.bob).boost(0, 1, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("0")

      await time.advanceBlockTo("3600")
      expect(await this.boostToken.getStakedTime(1)).to.be.above("0")
    })

    it("should be doubled reward when boosting", async function () {
      // 10 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "10",
        "10",
        "5000",
        "1000"
      )
      await this.chef.deployed()

      // Transfer 10,000 ANN to AnnexBoostFarm
      this.annex.transfer(this.chef.address, "100000")

      await this.chef.add("100", this.lp.address, true)
      expect(await this.chef.totalAllocPoint()).to.equal("100")

      await this.boostToken.gift(4, this.bob.address)
      await this.boostToken.setStakingAddress(this.chef.address)
      await this.boostToken.connect(this.bob).setApprovalForAll(this.chef.address, true, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("4")

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await this.chef.connect(this.bob).deposit(0, "10", { from: this.bob.address })
      expect(await this.lp.balanceOf(this.chef.address)).to.equal("10")

      await this.chef.connect(this.bob).boostAll(0, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("0")

      await time.advanceBlockTo("5010")
      expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("200")
    })

    it("should be doubled reward when boosting for 2 users", async function () {
      // 10 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "10",
        "10",
        "6000",
        "1000"
      )
      await this.chef.deployed()

      // Transfer 10,000 ANN to AnnexBoostFarm
      this.annex.transfer(this.chef.address, "100000")

      await this.chef.add("100", this.lp.address, true)
      expect(await this.chef.totalAllocPoint()).to.equal("100")

      await this.boostToken.gift(4, this.bob.address)
      await this.boostToken.gift(5, this.alice.address)
      await this.boostToken.setStakingAddress(this.chef.address)
      await this.boostToken.connect(this.bob).setApprovalForAll(this.chef.address, true, { from: this.bob.address })
      await this.boostToken.connect(this.alice).setApprovalForAll(this.chef.address, true, { from: this.alice.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("4")
      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("5")

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
      await this.chef.connect(this.bob).deposit(0, "10", { from: this.bob.address })
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      expect(await this.lp.balanceOf(this.chef.address)).to.equal("20")

      await this.chef.connect(this.bob).boostAll(0, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("0")
      await this.chef.connect(this.alice).boostAll(0, { from: this.alice.address })
      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("0")

      await time.advanceBlockTo("6009")
      // expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("83")
      // expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("116")

      await this.chef.connect(this.bob).deposit(0, "0", { from: this.bob.address })
      await this.chef.connect(this.alice).deposit(0, "0", { from: this.alice.address })
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("83")
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("128")
    })

    it("should be doubled reward when boosting for 2 users", async function () {
      // 10 per block farming rate starting at block 100 with bonus until block 1000
      this.chef = await this.AnnexBoostFarm.deploy(
        this.annex.address,
        this.boostToken.address,
        this.dev.address,
        "10",
        "10",
        "7000",
        "1000"
      )
      await this.chef.deployed()

      // Transfer 10,000 ANN to AnnexBoostFarm
      this.annex.transfer(this.chef.address, "100000")

      await this.chef.add("100", this.lp.address, true)
      expect(await this.chef.totalAllocPoint()).to.equal("100")

      await this.boostToken.gift(4, this.bob.address)
      await this.boostToken.gift(5, this.alice.address)

      await this.boostToken.setStakingAddress(this.chef.address)
      await this.boostToken.connect(this.bob).setApprovalForAll(this.chef.address, true, { from: this.bob.address })
      await this.boostToken.connect(this.alice).setApprovalForAll(this.chef.address, true, { from: this.alice.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("4")
      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("5")

      await this.lp.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
      await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
      await this.chef.connect(this.bob).deposit(0, "10", { from: this.bob.address })
      await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
      expect(await this.lp.balanceOf(this.chef.address)).to.equal("20")

      await this.chef.connect(this.bob).boostAll(0, { from: this.bob.address })
      expect(await this.boostToken.balanceOf(this.bob.address)).to.equal("0")
      await this.chef.connect(this.alice).boostAll(0, { from: this.alice.address })
      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("0")

      await time.advanceBlockTo("7010")
      expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("83")
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("116")

      // alice unboost one NFT
      await this.chef.connect(this.alice).unBoostPartially(0, 1, { from: this.alice.address })
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("128")
      await time.advanceBlockTo("7020")

      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("1")
      expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("181")
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("90")

      // unBoosting alice
      await this.chef.connect(this.alice).unBoostAll(0, { from: this.alice.address })
      expect(await this.boostToken.balanceOf(this.alice.address)).to.equal("5")
      await time.advanceBlockTo("7030")

      expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("326")
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("45")
      expect(await this.annex.balanceOf(this.alice.address)).to.equal("228")

      await this.chef.connect(this.bob).deposit(0, "0", { from: this.bob.address })
      await this.chef.connect(this.alice).deposit(0, "0", { from: this.alice.address })
      expect(await this.annex.balanceOf(this.bob.address)).to.equal("341")

      await time.advanceBlockTo("7041")
      expect(await this.chef.pendingAnnex(0, this.bob.address)).to.equal("150")
      expect(await this.chef.pendingAnnex(0, this.alice.address)).to.equal("45")
    })
  })
})
