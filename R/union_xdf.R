#' Set operations on data sources
#'
#' @param x,y Data sources.
#' @param .outFile Output format for the returned data. If not supplied, create an xdf tbl; if \code{NULL}, return a data frame; if a character string naming a file, save an Xdf file at that location.
#' @param .rxArgs A list of RevoScaleR arguments. See \code{\link{rxArgs}} for details.
#' @param ... Not currently used.
#'
#' @details
#' Currently, only \code{union} and \code{union_all} are supported for RevoScaleR data sources. The code uses \code{rxDataStep(append="rows")} to do the union; this can be much faster than using \code{rxMerge(type="union")}.
#'
#' For technical reasons, \code{union_all} is only exported as a method for RevoScaleR objects if you have dplyr version 0.5 or higher. If an earlier version of dplyr is installed, you can still call it but you'll have to specify the full function name: \code{union_all.RxFileData}. If this doesn't make sense to you, just assume that \code{union_all} requires dplyr 0.5.
#'
#' @return
#' An object representing the joined data. This depends on the \code{.outFile} argument: if missing, it will be an xdf tbl object; if \code{NULL}, a data frame; and if a filename, an Xdf data source referencing a file saved to that location.
#'
#' @seealso
#' \code{\link[dplyr]{setops}} in package dplyr
#' @aliases setops union union_all intersect setdiff setequal
#' @name setops
NULL

#' @importFrom dplyr union
#' @export
dplyr::union

#' @rdname setops
#' @export union_all.RxFileData
union_all.RxFileData <- function(x, y, .outFile, .rxArgs, ...)
{
    # need to create a new copy of x?
    # tbl -> tbl: ok
    # xdf -> tbl: copy
    # txt -> tbl: copy
    # tbl -> xdf: copy
    # xdf -> xdf: copy
    # txt -> xdf: copy
    copyBaseTable <- function(data, output)
    {
        # step through all possible combinations
        if(inherits(data, "tbl_xdf") && is.na(output))
            return(data)
        else if(inherits(data, "RxXdfData") && is.na(output))  # excludes data is tbl_xdf
        {
            oldData <- data
            if(hasTblFile(data))
                on.exit(deleteTbl(oldData))
            output <- tbl(newTbl(data), hasTblFile=TRUE)
            file.copy(data@file, output@file, overwrite=TRUE)
            return(output)
        }
        else if(inherits(data, "RxFileData") && is.na(output))
        {
            output <- tbl(data, stringsAsFactors=FALSE)
            return(output)
        }
        else if(inherits(data, "RxXdfData") && is.character(output))  # also includes data is tbl_xdf
        {
            oldData <- data
            if(hasTblFile(data))
                on.exit(deleteTbl(oldData))
            file.copy(data@file, output, overwrite=TRUE)
            return(RxXdfData(output))
        }
        else if(inherits(data, "RxFileData") && is.character(output))
        {
            outFile <- tbl(newTbl(data), hasTblFile=TRUE)
            return(tbl(data, file=output, overwrite=TRUE, stringsAsFactors=FALSE))
        }
        else stop("error handling base table in union", call.=TRUE)
    }

    stopIfHdfs(x, "joining not supported on HDFS")
    stopIfHdfs(y, "joining not supported on HDFS")

    dots <- lazyeval::lazy_dots(...)
    dots <- rxArgs(dots)

    exprs <- dots$exprs
    if(missing(.outFile)) .outFile <- NA
    if(missing(.rxArgs)) .rxArgs <- NULL
    grps <- groups(x)

    # if output is a data frame: convert x and y to df, run dplyr::union_all
    if(is.null(.outFile))
    {
        if(.dxOptions$dplyrVersion < package_version("0.5"))
        {
            warning("cannot output directly to data frame with dplyr version < 0.5")
            .outFile <- NA
        }
        else return(union_all(as.data.frame(x), as.data.frame(y)))
    }

    # use rxDataStep to append y to x, faster than rxMerge(type="union")
    # first, make a copy of x if necessary
    x <- copyBaseTable(x, .outFile)

    # if y points to same file as x, also make a copy
    # should only happen with union_all(x, x)
    if(inherits(y, "RxFileData") && y@file == x@file)
    {
        oldFile <- y@file
        y <- newTbl(y)
        file.copy(oldFile, y@file)
        on.exit(file.remove(y@file))
    }

    cl <- quote(rxDataStep(y, x, append="rows"))
    cl[names(.rxArgs)] <- .rxArgs

    x <- eval(cl)
    if(is.character(.outFile))  # do we want a persistent file?
        x <- as(x, "RxXdfData")
    simpleRegroup(x, grps)
}


#' @rdname setops
#' @export
union.RxFileData <- function(x, y, .outFile, .rxArgs, ...)
{
    stopIfHdfs(x, "joining not supported on HDFS")
    stopIfHdfs(y, "joining not supported on HDFS")

    # call union_all.RxFileData explicitly to allow use in dplyr < 0.5
    if(missing(.outFile))
        union_all.RxFileData(x, y, .rxArgs, ...) %>% distinct
    else
    {
        # horrible hack
        # TODO: figure out a better way of passing .outFile
        cl <- substitute(union_all.RxFileData(x, y, .rxArgs, ...) %>% distinct(.outFile=.outFile),
            list(.outFile=.outFile))
        eval(cl)
    }
}

