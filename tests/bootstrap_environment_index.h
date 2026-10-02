#ifndef PSL_TEST_ENVIRONMENT_INDEX_H
#define PSL_TEST_ENVIRONMENT_INDEX_H
#ifndef TEST_BUCKET_COUNT
#define TEST_BUCKET_COUNT 0
#endif
static uintptr_t test_buckets[16 * 1024];
#define TEST_INDEX_FIELDS .buckets=test_buckets, .bucket_count=TEST_BUCKET_COUNT, \
    .bucket_capacity=sizeof test_buckets / sizeof *test_buckets
#endif
