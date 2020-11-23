import {ethers} from 'hardhat';
import {expect} from '../chai-setup';

import {
    fromWei,
    toWei,
    getBalance,
    maxUint256,
    ADDRESS_ZERO, mineBlocks, getLatestBlockNumber
} from '../shared/utilities';

import {
    TToken, TTokenFactory,
    Bfi, BfiFactory,
    BearnChef, BearnChefFactory,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

const verbose = process.env.VERBOSE;

describe('001_bearn_chef.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let bfiToken: Bfi;
    let bearnChef: BearnChef;

    let lpToken: TToken;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];

        bfiToken = await new BfiFactory(deployer).deploy();

        bearnChef = await new BearnChefFactory(deployer).deploy(bfiToken.address, toWei('0.1'), 50);
        await bfiToken.mint(bearnChef.address, toWei('1000'));

        lpToken = await new TTokenFactory(deployer).deploy('BUSD', 'BUSD', 18);
        await lpToken.connect(bob).faucet(toWei('1000'));

        await lpToken.connect(bob).approve(bearnChef.address, maxUint256);
    })

    describe('BearnChef should work', () => {
        it('constructor parameters should be correct', async () => {
            expect(await bearnChef.owner()).is.eq(deployer.address);
            expect(await bearnChef.bfiPerBlock()).is.eq(toWei('0.1'));
            expect(await bearnChef.startBlock()).is.eq(50);
        });

        it('parameters should be correct', async () => {
            expect(await bearnChef.totalAllocPoint()).is.eq(0);
            expect(await bearnChef.poolLength()).is.eq(0);
        });

        it('add', async () => {
            await bearnChef.add(1000, lpToken.address, false, 100);
            expect(await bearnChef.poolLength()).is.eq(1);
            let poolInfo = await bearnChef.poolInfo(0);
            expect(poolInfo.isStarted).is.false;
            expect(poolInfo.lastRewardBlock).is.eq(100);
        });

        it('bob deposit 10 BUSD', async () => {
            await expect(async () => {
                await bearnChef.connect(bob).deposit(0, toWei('10'));
            }).to.changeTokenBalances(lpToken, [bob], [toWei('-10')]);
            await mineBlocks(ethers, 50);
            expect(await bearnChef.pendingBearn(0, bob.address)).is.eq(0);
            await mineBlocks(ethers, 51);
            expect(await getLatestBlockNumber(ethers)).is.eq(109);
            await expect(async () => {
                await bearnChef.connect(bob).withdraw(0, 0);
            }).to.changeTokenBalances(bfiToken, [bob], [toWei('1.0')]);
            await mineBlocks(ethers, 10);
            expect(await bearnChef.pendingBearn(0, bob.address)).is.eq(toWei('1.0'));
        });

        it('bob withdraw 5 BUSD', async () => {
            let _beforeBfi = await bfiToken.balanceOf(bob.address);
            await expect(async () => {
                await bearnChef.connect(bob).withdraw(0, toWei('5'));
            }).to.changeTokenBalances(lpToken, [bob], [toWei('5')]);
            let _afterBfi = await bfiToken.balanceOf(bob.address);
            expect(_afterBfi.sub(_beforeBfi)).is.eq(toWei('1.1'));
        });

        it('bob emergencyWithdraw', async () => {
            await mineBlocks(ethers, 10);
            expect(await bearnChef.pendingBearn(0, bob.address)).is.eq(toWei('1.0'));
            let _beforeBfi = await bfiToken.balanceOf(bob.address);
            await expect(async () => {
                await bearnChef.connect(bob).emergencyWithdraw(0);
            }).to.changeTokenBalances(lpToken, [bob], [toWei('5')]);
            let _afterBfi = await bfiToken.balanceOf(bob.address);
            expect(_afterBfi.sub(_beforeBfi)).is.eq(toWei('0'));
        });
    });
});
