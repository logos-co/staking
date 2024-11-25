// Summary for OpenZeppelin's Math.
methods
{
    function Math.max(uint256 a, uint256 b) internal returns (uint256) => maxSummary(a, b);
    function Math.min(uint256 a, uint256 b) internal returns (uint256) => minSummary(a, b);
    function Math.average(uint256 a, uint256 b) internal returns (uint256) => averageSummary(a, b);
    function Math.ceilDiv(uint256 a, uint256 b) internal returns (uint256) => ceilDivSummary(a, b);
    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns (uint256) => mulDivSummary(x, y, denominator);
    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator, Math.Rounding rounding) internal returns (uint256) => mulDivSummaryRounding(x, y, denominator, rounding);
}

function maxSummary(uint256 a, uint256 b) returns uint256
{
    return a > b ? a : b;
}

function minSummary(uint256 a, uint256 b) returns uint256
{
    return a < b ? a : b;
}

function averageSummary(uint256 a, uint256 b) returns uint256
{
    return require_uint256((a + b) / 2);
}

function ceilDivSummary(uint256 numerator, uint256 denominator) returns uint256 {
    require denominator > 0;
    return require_uint256((numerator + denominator - 1) / denominator);
}

function mulDivSummary(uint256 x, uint256 y, uint256 denominator) returns uint256 {
    require denominator > 0;
    return require_uint256((x * y) / denominator);
}

function mulDivSummaryRounding(uint256 x, uint256 y, uint256 denominator, Math.Rounding rounding) returns uint256 {
    require denominator > 0;
    if (rounding == Math.Rounding.Up) {
        return require_uint256(((x * y) + denominator - 1) / denominator);
    } else {
        return require_uint256((x * y) / denominator);
    }
}
