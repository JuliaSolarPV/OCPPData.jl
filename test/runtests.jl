using TestItemRunner

@run_package_tests verbose = true filter = ti -> !(:crossvalidation in ti.tags)
