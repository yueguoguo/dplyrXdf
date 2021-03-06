#' @include summarise_xdf.R
#' @include summarise_xdf_summary.R
NULL


smry_rxSummary2 <- function(data, grps=NULL, stats, exprs, rxArgs)
{
    # should always have groups
    if(is.null(grps))
        stop("no grouping variables supplied", call.=FALSE)

    outvars <- names(exprs)
    invars <- invars(exprs)

    levs <- get_grouplevels(data)

    output <- newTbl(data)
    if(hasTblFile(data))
        on.exit(deleteTbl(data))

    # put grouping variable on to dataset
    output <- rxDataStep(data, output, transformFunc=function(varlst) {
        varlst[[".group."]] <- .factor(varlst, .levs)
        varlst
    }, transformObjects=list(.levs=levs, .factor=make_groupvar), transformVars=grps, overwrite=TRUE)
    output <- as(output, "grouped_tbl_xdf")
    output@groups <- grps
    output@hasTblFile <- TRUE

    smry <- smry_rxSummary(output, ".group.", stats, exprs, rxArgs)
    
    # unsplit the grouping variable
    vars <- rebuild_groupvars(smry[1], grps, data)

    data.frame(vars, smry[-1], stringsAsFactors=FALSE)
}

