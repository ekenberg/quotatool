/*
 * Minimal test: call quotactl Q_SETQUOTA and Q_SYNC separately
 * to determine which one hangs on OpenBSD.
 *
 * Build:  gcc -o test-quotactl test-quotactl.c
 * Usage:  ./test-quotactl /mnt/quota-test 60000
 */
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <ufs/ufs/quota.h>
#include <string.h>
#include <errno.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <mountpoint> <uid>\n", argv[0]);
        return 1;
    }

    char *mountpoint = argv[1];
    int uid = atoi(argv[2]);
    char qfile[256];
    struct dqblk dq;
    int ret;

    snprintf(qfile, sizeof(qfile), "%s/quota.user", mountpoint);
    printf("quota file: %s\n", qfile);
    printf("uid: %d\n", uid);

    /* Step 1: Q_GETQUOTA (should work) */
    printf("\n[1] Q_GETQUOTA... ");
    fflush(stdout);
    memset(&dq, 0, sizeof(dq));
    ret = quotactl(qfile, QCMD(Q_GETQUOTA, USRQUOTA), uid, (caddr_t)&dq);
    printf("ret=%d (errno=%d: %s)\n", ret, errno, ret < 0 ? strerror(errno) : "OK");
    printf("    soft=%u hard=%u used=%u\n", dq.dqb_bsoftlimit, dq.dqb_bhardlimit, dq.dqb_curblocks);

    /* Step 2: Q_SETQUOTA with only limits changed */
    printf("\n[2] Q_SETQUOTA (soft=200, hard=400)... ");
    fflush(stdout);
    dq.dqb_bsoftlimit = 200;  /* 200 blocks = 100K on 512-byte blocks */
    dq.dqb_bhardlimit = 400;
    ret = quotactl(qfile, QCMD(Q_SETQUOTA, USRQUOTA), uid, (caddr_t)&dq);
    printf("ret=%d (errno=%d: %s)\n", ret, errno, ret < 0 ? strerror(errno) : "OK");

    /* Step 3: Q_SYNC */
    printf("\n[3] Q_SYNC... ");
    fflush(stdout);
    ret = quotactl(qfile, QCMD(Q_SYNC, USRQUOTA), 0, NULL);
    printf("ret=%d (errno=%d: %s)\n", ret, errno, ret < 0 ? strerror(errno) : "OK");

    /* Step 4: Verify via Q_GETQUOTA */
    printf("\n[4] Q_GETQUOTA (verify)... ");
    fflush(stdout);
    memset(&dq, 0, sizeof(dq));
    ret = quotactl(qfile, QCMD(Q_GETQUOTA, USRQUOTA), uid, (caddr_t)&dq);
    printf("ret=%d\n", ret);
    printf("    soft=%u hard=%u used=%u\n", dq.dqb_bsoftlimit, dq.dqb_bhardlimit, dq.dqb_curblocks);

    printf("\nDone.\n");
    return 0;
}
