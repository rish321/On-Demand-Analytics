#  File src/library/utils/R/completion.R
#  Part of the R package, http://www.R-project.org
#
# Copyright (C) 2006  Deepayan Sarkar <Deepayan.Sarkar@R-project.org>
# Copyright (C) 2006-2012  The R Core Team
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  A copy of the GNU General Public License is available at
#  http://www.r-project.org/Licenses/



### Note: By default, we try not to do things that might be slow due
### to network latency (think NFS).  For example, retrieving a list of
### available packages is potentially slow, and is thus disabled
### initially.


### Status: I'm mostly happy with things.  The only obvious
### improvement I can think of is figuring out when we are in
### continuation mode (R prompt == "+") and make use of previous lines
### in that case.  I haven't found a way to do that.



### Note: sprintf seems faster than paste based on naive benchmarking:

## > system.time(for (i in 1L:100000L) sprintf("foo%sbar%d", letters, 1L:26L) )
##            user          system           total   user.children system.children
##           4.796           0.088           4.887           0.000           0.000
## > system.time(for (i in 1L:100000L) paste("foo", letters, "bar", 1L:26L) )
##            user          system           total   user.children system.children
##           8.300           0.028           8.336           0.000           0.000

### so will change all pastes to sprintf.  However, we need to be
### careful because 0 length components in sprintf will cause errors.


## generic and built-in methods to generate completion after $

.DollarNames <- function(x, pattern)
    UseMethod(".DollarNames")

.DollarNames.default <- function(x, pattern = "") {
    if (is.atomic(x) || is.symbol(x)) character()
    else grep(pattern, names(x), value = TRUE)
}

.DollarNames.list <- function(x, pattern = "") {
    grep(pattern, names(x), value = TRUE)
}

.DollarNames.environment <- function(x, pattern = "") {
    ls(x, all.names = TRUE, pattern = pattern)
}

## if (is.environment(object))
## {
##     ls(object,
##        all.names = TRUE,
##        pattern = sprintf("^%s", makeRegexpSafe(suffix)))
## }
## else
## {
##     grep(sprintf("^%s", makeRegexpSafe(suffix)),
##          names(object), value = TRUE)
## }




## modifies settings:

rc.settings <- function(ops, ns, args, func, ipck, S3, data, help, argdb, files)
{
    checkAndChange <- function(what, value)
    {
        if ((length(value) == 1L) &&
            is.logical(value) &&
            !is.na(value))
            .CompletionEnv$settings[[what]] <- value
    }
    if (!missing(ops))   checkAndChange(  "ops",   ops)
    if (!missing(ns))    checkAndChange(   "ns",    ns)
    if (!missing(args))  checkAndChange( "args",  args)
    if (!missing(func))  checkAndChange( "func",  func)
    if (!missing(ipck))  checkAndChange( "ipck",  ipck)
    if (!missing(S3))    checkAndChange(   "S3",    S3)
    if (!missing(data))  checkAndChange( "data",  data)
    if (!missing(help))  checkAndChange( "help",  help)
    if (!missing(argdb)) checkAndChange("argdb", argdb)
    if (!missing(files)) checkAndChange("files", files)
    invisible()
}





## modifies options (adapted from similar functions in lattice):

rc.getOption <- function(name)
{
    get("options", envir = .CompletionEnv)[[name]]
}

rc.options <- function(...)
{
    new <- list(...)
    if (is.null(names(new)) && length(new) == 1L && is.list(new[[1L]]))
        new <- new[[1L]]
    old <- .CompletionEnv$options

    ## if no args supplied, returns full options list
    if (length(new) == 0L) return(old)
    ## typically getting options
    nm <- names(new)
    if (is.null(nm)) return(old[unlist(new)])

    isNamed <- nm != ""
    if (any(!isNamed)) nm[!isNamed] <- unlist(new[!isNamed])

    ## so now everything has non-"" names, but only the isNamed ones
    ## should be set.  Everything should be returned though.

    retVal <- old[nm]
    names(retVal) <- nm
    nm <- nm[isNamed]
    .CompletionEnv$options <- modifyList(old, new[nm])
    invisible(retVal)
}



## summarizes results of last completion attempt:

rc.status <- function()
{
    ## eapply(.CompletionEnv, function(x) x, all.names = TRUE)
    as.list(.CompletionEnv)
}


### Everything below is unexported


## accessors called from C (also .completeToken below):

.assignToken         <- function(text)  assign("token",      text,  envir = .CompletionEnv)
.assignLinebuffer    <- function(line)  assign("linebuffer", line,  envir = .CompletionEnv)
.assignStart         <- function(start) assign("start",      start, envir = .CompletionEnv)
.assignEnd           <- function(end)   assign("end",        end,   envir = .CompletionEnv)
.setFileComp         <- function(state) assign("fileName",   state, envir = .CompletionEnv)

.retrieveCompletions <- function()  unique(get("comps",             envir = .CompletionEnv))
.getFileComp         <- function()         get("fileName",          envir = .CompletionEnv)




## The following function is not required for GNU readline, but can be
## useful if one needs to break a line into tokens.  It requires
## linebuffer and end to be already set, and itself sets token and
## start.  It returns the token.

## FIXME: should this use getOption("rl_word_breaks")?

.guessTokenFromLine <-
    function(linebuffer = .CompletionEnv[["linebuffer"]],
             end = .CompletionEnv[["end"]])
{
    ## special rules apply when we are inside quotes (see fileCompletionPreferred() below)
    insideQuotes <- {
        lbss <- head.default(unlist(strsplit(linebuffer, "")), .CompletionEnv[["end"]])
        ((sum(lbss == "'") %% 2 == 1) ||
         (sum(lbss == '"') %% 2 == 1))
    }
    start <-
        if (insideQuotes)
            ## set 'start' to the location of the last quote
            suppressWarnings(gregexpr("['\"]",
                                      substr(linebuffer, 1L, end),
                                      perl = TRUE))[[1L]]
            ## suppressWarnings(gregexpr("[^\\.\\w:?$@[\\]\\\\/~ ]+", substr(linebuffer, 1L, end), perl = TRUE))[[1L]]
        else
            ##                    things that should not cause breaks
            ##                           ______________
            suppressWarnings(gregexpr("[^\\.\\w:?$@[\\]]+",
                                      substr(linebuffer, 1L, end),
                                      perl = TRUE))[[1L]]
    start <- ## 0-indexed
        if (all(start < 0L)) 0L
        else tail.default(start + attr(start, "match.length"), 1L) - 1L
    .CompletionEnv[["start"]] <- start
    .CompletionEnv[["token"]] <- substr(linebuffer, start + 1L, end)
    .CompletionEnv[["token"]]
}






## convert a string to something that escapes special regexp
## characters.  Doesn't have to be perfect, especially for characters
## that would cause breaks or be handled elsewhere.  All we really
## need is to handle ".", so that e.g. "heat." doesn't match
## "heatmap".


makeRegexpSafe <- function(s)
{
    ## the following can cause errors otherwise
    s <- gsub("\\", "\\\\", s, fixed = TRUE) ## has to be the first
    s <- gsub("(", "\\(", s, fixed = TRUE)
    s <- gsub("*", "\\*", s, fixed = TRUE)
    s <- gsub("+", "\\+", s, fixed = TRUE)
    s <- gsub("?", "\\?", s, fixed = TRUE)
    s <- gsub("[", "\\[", s, fixed = TRUE)
    s <- gsub("{", "\\{", s, fixed = TRUE)
    ## s <- gsub("]", "\\]", s, fixed = TRUE) # necessary?
    ## these are wildcards that we want to interpret literally
    s <- gsub(".", "\\.", s, fixed = TRUE)
    s <- gsub("^", "\\^", s, fixed = TRUE)
    ## what else?
    s
}



## Operators that are handled specially.  Order is important, ::: must
## come before :: (because :: will match :::)

specialOps <- c("$", "@", ":::", "::", "?", "[", "[[")



specialOpLocs <- function(text)
{
    ## does text contain a special operator?  There may be multiple
    ## occurrences, and we want the last one (whereas regexpr gives
    ## the first). So...

    ge <-
        sapply(specialOps,
               function(s) gregexpr(s, text, fixed = TRUE)[[1L]],
               simplify = FALSE)
    ## this gets the last ones
    ge <- sapply(ge, tail.default, 1)
    ge <- ge[ge > 0]
}



## accessing the help system: should allow anything with an index entry
## this just looks at packages on the search path.

matchAvailableTopics <- function(text)
{
    .readAliases <- function(path) {
        if(file.exists(f <- file.path(path, "help", "aliases.rds")))
            names(readRDS(f))
        else if(file.exists(f <- file.path(path, "help", "AnIndex")))
            ## aliases.rds was introduced before 2.10.0, as can phase this out
            scan(f, what = list("", ""), sep = "\t", quote = "",
                 na.strings = "", quiet = TRUE)[[1L]]
        else character()
    }
    if (length(text) != 1L || text == "") return (character())
    pkgpaths <- searchpaths()[substr(search(), 1L, 8L) == "package:"]
    aliases <- unique(unlist(lapply(pkgpaths, .readAliases)))
    grep(sprintf("^%s", makeRegexpSafe(text)), aliases, value = TRUE)
}



## this is for requests of the form ?suffix[TAB] or prefix?suffix[TAB]

## can be improved when prefix is non-trivial, but that is rarely used
## (on the other hand, can be useful for exploring S4 methods; but
## usage of ? needs to be fixed in R first).  Anyway, that case is not
## currently handled

helpCompletions <- function(prefix, suffix)
{
    nc <-
        if (.CompletionEnv$settings[["help"]])
            matchAvailableTopics(suffix)
        else
            normalCompletions(suffix, check.mode = FALSE)
    if (length(nc)) sprintf("%s?%s", prefix, nc)
    else character()
}


specialCompletions <- function(text, spl)
{

    ## we'll only try to complete after the last special operator, and
    ## assume that everything before is meaningfully complete.  A more
    ## sophisticated version of this function may decide to do things
    ## differently.

    ## Note that this will involve evaluations, which may have side
    ## effects.  This (side-effects) would not happen normally (except
    ## of lazy loaded symbols, which most likely would have been
    ## evaluated shortly anyway), because explicit function calls
    ## (with parentheses) are not evaluated.  In any case, these
    ## evaluations won't happen if settings$ops==FALSE

    ## spl (locations of matches) is guaranteed to be non-empty

    wm <- which.max(spl)
    op <- names(spl)[wm]
    opStart <- spl[wm]
    opEnd <- opStart + nchar(op)

    if (opStart < 1) return(character()) # shouldn't happen
    prefix <- substr(text, 1L, opStart - 1L)
    suffix <- substr(text, opEnd, 1000000L)

    if (op == "?") return(helpCompletions(prefix, suffix))

    if (opStart <= 1) return(character()) # not meaningful

    ## ( breaks words, so prefix should not involve function calls,
    ## and thus, hopefully no side-effects.

    tryToEval <- function(s)
    {
        try(eval(parse(text = s), envir = .GlobalEnv), silent = TRUE)
    }

    comps <-
        switch(op,
               "$" = {
                   if (.CompletionEnv$settings[["ops"]])
                   {
                       object <- tryToEval(prefix)
                       if (inherits(object, "try-error")) ## nothing else to do
                           suffix
                       else
                       {
                           ## ## suffix must match names(object) (or ls(object) for environments)
                           .DollarNames(object, pattern = sprintf("^%s", makeRegexpSafe(suffix)))
                           ## if (is.environment(object))
                           ## {
                           ##     ls(object,
                           ##        all.names = TRUE,
                           ##        pattern = sprintf("^%s", makeRegexpSafe(suffix)))
                           ## }
                           ## else
                           ## {
                           ##     grep(sprintf("^%s", makeRegexpSafe(suffix)),
                           ##          names(object), value = TRUE)
                           ## }
                       }
                   } else suffix
               },
               "@" = {
                   if (.CompletionEnv$settings[["ops"]])
                   {
                       object <- tryToEval(prefix)
                       if (inherits(object, "try-error")) ## nothing else to do
                           suffix
                       else
                       {
                           grep(sprintf("^%s", makeRegexpSafe(suffix)),
                                methods::slotNames(object), value = TRUE)
                       }
                   } else suffix
               },
               "::" = {
                   if (.CompletionEnv$settings[["ns"]])
                   {
                       nse <- try(getNamespaceExports(prefix), silent = TRUE)
                       if (inherits(nse, "try-error")) ## nothing else to do
                           suffix
                       else
                       {
                           grep(sprintf("^%s", makeRegexpSafe(suffix)),
                                nse, value = TRUE)
                       }
                   } else suffix
               },
               ":::" = {
                   if (.CompletionEnv$settings[["ns"]])
                   {
                       ns <- try(getNamespace(prefix), silent = TRUE)
                       if (inherits(ns, "try-error")) ## nothing else to do
                           suffix
                       else
                       {
                           ls(ns,
                              all.names = TRUE,
                              pattern = sprintf("^%s", makeRegexpSafe(suffix)))
                       }
                   } else suffix
               },
               "[" = ,  # can't think of anything else to do
               "[[" = {
                   comps <- normalCompletions(suffix)
                   if (length(comps)) comps
                   else suffix
               })
    if (length(comps) == 0L) comps <- ""
    sprintf("%s%s%s", prefix, op, comps)
}



## completions on special keywords (subset of those in gram.c).  Some
## issues with parentheses: e.g. mode(get("repeat")) is "function", so
## it is normally completed with a left-paren appended, but that is
## not normal usage.  Putting it here means that both 'repeat' and
## 'repeat(' will be valid completions (as they should be)


keywordCompletions <- function(text)
{
    grep(sprintf("^%s", makeRegexpSafe(text)),
         c("NULL", "NA", "TRUE", "FALSE", "Inf", "NaN",
           "NA_integer_", "NA_real_", "NA_character_", "NA_complex_",
           "repeat ", "in ", "next ", "break ", "else "),
         value = TRUE)
}




## 'package' environments in the search path.  These will be completed
## with a :: IIRC, that works even if there's no namespace, but I
## haven't actually checked.



attachedPackageCompletions <- function(text, add = rc.getOption("package.suffix"))
{
    if (.CompletionEnv$settings[["ns"]])
    {
        s <- grep("^package", search(), value = TRUE)
        comps <-
            grep(sprintf("^%s", makeRegexpSafe(text)),
                 substr(s, 9L, 1000000L),
                 value = TRUE)
        if (length(comps) && !is.null(add))
            sprintf("%s%s", comps, add)
        else
            comps
    }
    else character()
}



## this provides the most basic completion, looking for completions in
## the search path using apropos, plus keywords.  Plus completion on
## attached packages if settings$ns == TRUE


normalCompletions <-
    function(text, check.mode = TRUE,
             add.fun = rc.getOption("function.suffix"))
{
    ## use apropos or equivalent
    if (text == "") character() ## too many otherwise
    else
    {
        comps <- apropos(sprintf("^%s", makeRegexpSafe(text)), ignore.case = FALSE)
        if (.CompletionEnv$settings[["func"]] && check.mode && !is.null(add.fun))
        {
            which.function <- sapply(comps, function(s) exists(s, mode = "function"))
            if (any(which.function))
                comps[which.function] <-
                    sprintf("%s%s", comps[which.function], add.fun)
            ##sprintf("\033[31m%s\033[0m%s", comps[which.function], add.fun)
        }
        c(comps, keywordCompletions(text), attachedPackageCompletions(text))
    }
}


## completion on function arguments.  This involves the most work (as
## we need to look back in the line buffer to figure out which
## function we are inside, if any), and is also potentially intensive
## when many functions match the function that we are supposedly in
## (which will happen for common generic functions like print (we are
## very optimistic here, erring on the side of
## whatever-the-opposite-of-caution-is (our justification being that
## erring on the side of caution is practically useless and not erring
## at all is expensive to the point of being impossible (we really
## don't want to evaluate the dotplot() call in "print(dotplot(x),
## positi[TAB] )" ))))


## this defines potential function name boundaries

breakRE <- "[^\\.\\w]"
## breakRE <- "[ \t\n \\\" '`><=-%;,&}\\\?\\\+\\\{\\\|\\\(\\\)\\\*]"




## for some special functions like library, data, etc, normal
## completion is rarely meaningful, especially for the first argument.
## Unfortunately, knowing whether the token being completed is the
## first arg of such a function involves more work than we would
## normally want to do.  On the other hand, inFunction() below already
## does most of this work, so we will add a piece of code (mostly
## irrelevant to its primary purpose) to indicate this.  The following
## two functions are just wrappers to access and modify this
## information.


setIsFirstArg <- function(v)
    .CompletionEnv[["isFirstArg"]] <- v

getIsFirstArg <- function()
    .CompletionEnv[["isFirstArg"]]



inFunction <-
    function(line = .CompletionEnv[["linebuffer"]],
             cursor = .CompletionEnv[["start"]])
{
    ## are we inside a function? Yes if the number of ( encountered
    ## going backwards exceeds number of ).  In that case, we would
    ## also like to know what function we are currently inside
    ## (ideally, also what arguments to it have already been supplied,
    ## but let's not dream that far ahead).

    parens <-
        sapply(c("(", ")"),
               function(s) gregexpr(s, substr(line, 1L, cursor), fixed = TRUE)[[1L]],
               simplify = FALSE)
    ## remove -1's
    parens <- lapply(parens, function(x) x[x > 0])

    ## The naive algo is as follows: set counter = 0; go backwards
    ## from cursor, set counter-- when a ) is encountered, and
    ## counter++ when a ( is encountered.  We are inside a function
    ## that starts at the first ( with counter > 0.

    temp <-
        data.frame(i = c(parens[["("]], parens[[")"]]),
                   c = rep(c(1, -1), sapply(parens, length)))
    if (nrow(temp) == 0) return(character())
    temp <- temp[order(-temp$i), , drop = FALSE] ## order backwards
    wp <- which(cumsum(temp$c) > 0)
    if (length(wp)) # inside a function
    {
        ## return guessed name of function, letting someone else
        ## decide what to do with that name

        index <- temp$i[wp[1L]]
        prefix <- substr(line, 1L, index - 1L)
        suffix <- substr(line, index + 1L, cursor + 1L)

        ## note in passing whether we are the first argument (no '='
        ## and no ',' in suffix)

        if ((length(grep("=", suffix, fixed = TRUE)) == 0L) &&
            (length(grep(",", suffix, fixed = TRUE)) == 0L))
            setIsFirstArg(TRUE)


        if ((length(grep("=", suffix, fixed = TRUE))) &&
            (length(grep(",", substr(suffix,
                                     tail.default(gregexpr("=", suffix, fixed = TRUE)[[1L]], 1L),
                                     1000000L), fixed = TRUE)) == 0L))
        {
            ## we are on the wrong side of a = to be an argument, so
            ## we don't care even if we are inside a function
            return(character())
        }
        else ## guess function name
        {
            possible <- suppressWarnings(strsplit(prefix, breakRE, perl = TRUE))[[1L]]
            possible <- possible[possible != ""]
            if (length(possible)) return(tail.default(possible, 1))
            else return(character())
        }
    }
    else # not inside function
    {
        return(character())
    }
}


argNames <-
    function(fname, use.arg.db = .CompletionEnv$settings[["argdb"]])
{
    if (use.arg.db) args <- .FunArgEnv[[fname]]
    if (!is.null(args)) return(args)
    ## else
    args <- do.call(argsAnywhere, list(fname))
    if (is.null(args))
        character()
    else if (is.list(args))
        unlist(lapply(args, function(f) names(formals(f))))
    else
        names(formals(args))
}



specialFunctionArgs <- function(fun, text)
{
    ## certain special functions have special possible arguments.
    ## This is primarily applicable to library and require, for which
    ## rownames(installed.packages()).  This is disabled by default,
    ## because the first call to installed.packages() can be time
    ## consuming, e.g. on a network file system.  However, the results
    ## are cached, so subsequent calls are not that expensive.

    switch(EXPR = fun,

           library = ,
           require = {
               if (.CompletionEnv$settings[["ipck"]])
               {
                   grep(sprintf("^%s", makeRegexpSafe(text)),
                        rownames(installed.packages()), value = TRUE)
               }
               else character()
           },

           data = {
               if (.CompletionEnv$settings[["data"]])
               {
                   grep(sprintf("^%s", makeRegexpSafe(text)),
                        data()$results[, "Item"], value = TRUE)
               }
               else character()
           },

           ## otherwise,
           character())
}



functionArgs <-
    function(fun, text,
             S3methods = .CompletionEnv$settings[["S3"]],
             S4methods = FALSE,
             add.args = rc.getOption("funarg.suffix"))
{
    if (length(fun) < 1L || any(fun == "")) return(character())
    specialFunArgs <- specialFunctionArgs(fun, text)
    if (S3methods && exists(fun, mode = "function"))
        fun <-
            c(fun,
              tryCatch(methods(fun),
                       warning = function(w) {},
                       error = function(e) {}))
    if (S4methods)
        warning("Can't handle S4 methods yet")
    allArgs <- unique(unlist(lapply(fun, argNames)))
    ans <-
        grep(sprintf("^%s", makeRegexpSafe(text)),
             allArgs, value = TRUE)
    if (length(ans) && !is.null(add.args))
        ans <- sprintf("%s%s", ans, add.args)
    c(specialFunArgs, ans)
}



## Note: Inside the C code, we redefine
## rl_attempted_completion_function rather than
## rl_completion_entry_function, which means that if
## retrieveCompletions() returns a length-0 result, by default the
## fallback filename completion mechanism will be used.  This is not
## quite the best way to go, as in certain (most) situations filename
## completion will definitely be inappropriate even if no valid R
## completions are found.  We could return "" as the only completion,
## but that produces an irritating blank line on
## list-possible-completions (or whatever the correct name is).
## Instead (since we don't want to reinvent the wheel), we use the
## following scheme: If the character just preceding our token is " or
## ', we immediately go to file name completion.  If not, we do our
## stuff, and disable file name completion (using
## .Call("RCSuppressFileCompletion")) even if we don't find any
## matches.

## Note that under this scheme, filename completion will fail
## (possibly in unexpected ways) if the partial name contains 'unusual
## characters', namely ones that have been set (see C code) to cause a
## word break because doing so is meaningful in R syntax (e.g. "+",
## "-" ("/" is exempt (and treated specially below) because of its
## ubiquitousness in UNIX file names (where this package is most
## likely to be used))


## decide whether to fall back on filename completion.  Yes if the
## number of quotes between the cursor and the beginning of the line
## is an odd number.

isInsideQuotes <-
fileCompletionPreferred <- function()
{
    ((st <- .CompletionEnv[["start"]]) > 0 && {

        ## yes if the number of quote signs to the left is odd
        linebuffer <- .CompletionEnv[["linebuffer"]]
        lbss <- head.default(unlist(strsplit(linebuffer, "")), .CompletionEnv[["end"]])
        ((sum(lbss == "'") %% 2 == 1) ||
         (sum(lbss == '"') %% 2 == 1))

    })
}


## File name completion, used if settings$files == TRUE.  Front ends
## that can do filename completion themselves should probably not use
## this as they will do a better job.

correctFilenameToken <- function()
{
    ## Helper function

    ## If a file name contains spaces, the token will only have the
    ## part after the last space.  This function tries to recover the
    ## complete initial part.

    ## Find part between last " or '
    linebuffer <- .CompletionEnv[["linebuffer"]]
    lbss <- head.default(unlist(strsplit(linebuffer, "")), .CompletionEnv[["end"]])
    whichDoubleQuote <- lbss == '"'
    whichSingleQuote <- lbss == "'"
    insideDoubleQuote <- (sum(whichDoubleQuote) %% 2 == 1)
    insideSingleQuote <- (sum(whichSingleQuote) %% 2 == 1)
    loc.start <-
        if (insideDoubleQuote && insideSingleQuote)
        {
            ## Should not happen, but if it does, should take whichever comes later
            max(which(whichDoubleQuote), which(whichSingleQuote))
        }
        else if (insideDoubleQuote)
            max(which(whichDoubleQuote))
        else if (insideSingleQuote)
            max(which(whichSingleQuote))
        else ## should not happen, abort non-intrusively
            .CompletionEnv[["start"]]
    substring(linebuffer, loc.start + 1L, .CompletionEnv[["end"]])
}




fileCompletions <- function(token)
{
    ## uses Sys.glob (conveniently introduced in 2.5.0)

    ## token may not start just after the begin quote, e.g., if spaces
    ## are included.  Get 'correct' partial file name by looking back
    ## to begin quote
    pfilename <- correctFilenameToken()

    ## Sys.glob doesn't work without expansion.  Is that intended?
    pfilename.expanded <- path.expand(pfilename)
    comps <- Sys.glob(sprintf("%s*", pfilename.expanded), dirmark = TRUE)

    ## for things that only extend beyond the cursor, need to
    ## 'unexpand' path
    if (pfilename.expanded != pfilename)
        comps <- sub(path.expand("~"), "~", comps, fixed = TRUE)

    ## for tokens that were non-trivially corrected by adding prefix,
    ## need to delete extra part
    if (pfilename != token)
        comps <- substring(comps, nchar(pfilename) - nchar(token) + 1L, 1000L)

    comps
}





## .completeToken() is the primary interface, and does the actual
## completion when called from C code.


.completeToken <- function()
{
    text <- .CompletionEnv[["token"]]
    if (isInsideQuotes())
    {

        ## If we're in here, that means we think the cursor is inside
        ## quotes.  In most cases, this means that standard filename
        ## completion is more appropriate, but probably not if we're
        ## trying to access things of the form x["foo... or x$"foo...
        ## The following tries to figure this out, but it won't work
        ## in all cases (e.g. x[, "foo<TAB>"])

        ## We assume that whoever determines our token boundaries
        ## considers quote signs as a breaking symbol.

        st <- .CompletionEnv[["start"]]
        probablyNotFilename <-
            (st > 2L &&
             (substr(.CompletionEnv[["linebuffer"]], st-1L, st-1L) %in% c("[", ":", "$")))


        ## If the 'files' setting is FALSE, we will make no attempt to
        ## do filename completion (this is likely to happen with
        ## front-ends that are capable of doing their own file name
        ## completion; such front-ends can fall back to their native
        ## file completion when rc.status("fileName") is TRUE.

        if (.CompletionEnv$settings[["files"]])
        {

            ## we bail out if probablyNotFilename == TRUE.  If we
            ## wanted to be really fancy, we could try to detect where
            ## we are and act accordingly, e.g. if it's
            ## foo[["bar<TAB>, pretend we are completing foo$bar, etc.
            ## This is not that hard, we just need to use
            ## .guessTokenFromLine(linebuffer, end = st - 1) to get the
            ## 'foo[[' part.

            .CompletionEnv[["comps"]] <-
                if (probablyNotFilename) character()
                else fileCompletions(text)
            .setFileComp(FALSE)
        }
        else
        {
            .CompletionEnv[["comps"]] <- character()
            .setFileComp(TRUE)
        }

    }
    else
    {
        .setFileComp(FALSE)
        setIsFirstArg(FALSE) # might be changed by inFunction() call
        ## make a guess at what function we are inside
        guessedFunction <-
            if (.CompletionEnv$settings[["args"]])
                inFunction(.CompletionEnv[["linebuffer"]],
                           .CompletionEnv[["start"]])
            else ""
        .CompletionEnv[["fguess"]] <- guessedFunction

        ## if this is not "", then we want to add possible arguments
        ## of that function(s) (methods etc).  Should be character()
        ## if nothing matches

        fargComps <- functionArgs(guessedFunction, text)

        if (getIsFirstArg() && length(guessedFunction) &&
            guessedFunction %in%
            c("library", "require", "data"))
        {
            .CompletionEnv[["comps"]] <- fargComps
            ## don't try anything else
            return()
        }

        ## Is there an arithmetic operator in there in there?  If so,
        ## work on the part after that and append to prefix before
        ## returning.  It would have been easier if these were
        ## word-break characters, but that potentially interferes with
        ## filename completion.

        ## lastArithOp <- tail(gregexpr("/", text, fixed = TRUE)[[1L]], 1)
        lastArithOp <- tail.default(gregexpr("[\"'^/*+-]", text)[[1L]], 1)
        if (haveArithOp <- (lastArithOp > 0))
        {
            prefix <- substr(text, 1L, lastArithOp)
            text <- substr(text, lastArithOp + 1L, 1000000L)
        }

        spl <- specialOpLocs(text)
        comps <-
            if (length(spl))
                specialCompletions(text, spl)
            else
            {
                ## should we append a left-paren for functions?
                ## Usually yes, but not when inside certain special
                ## functions which often take other functions as
                ## arguments

                appendFunctionSuffix <-
                    !any(guessedFunction %in%

                         c("help", "args", "formals", "example",
                           "do.call", "environment", "page", "apply",
                           "sapply", "lapply", "tapply", "mapply",
                           "methods", "fix", "edit"))

                normalCompletions(text, check.mode = appendFunctionSuffix)
            }
        if (haveArithOp && length(comps))
        {
            comps <- paste0(prefix, comps)
        }
        comps <- c(comps, fargComps)
        .CompletionEnv[["comps"]] <- comps
    }
}



## support functions that attempt to provide tools useful specifically
## for the Windows Rgui.


## Note: even though these are unexported functions, changes in the
## API should be noted in man/rcompgen.Rd


.win32consoleCompletion <-
    function(linebuffer, cursorPosition,
             check.repeat = TRUE,
             minlength = -1)
{
    isRepeat <- ## is TAB being pressed repeatedly with this combination?
        if (check.repeat)
            (linebuffer == .CompletionEnv[["linebuffer"]] &&
             cursorPosition == .CompletionEnv[["end"]])
        else TRUE

    .assignLinebuffer(linebuffer)
    .assignEnd(cursorPosition)
    .guessTokenFromLine()
    token <- .CompletionEnv[["token"]]
    comps <-
        if (nchar(token, type = "chars") < minlength) character()
        else
        {
            .completeToken()
            .retrieveCompletions()
        }

    ## FIXME: no idea how much of this is MBCS-safe

    if (length(comps) == 0L)
    {
        ## no completions
        addition <- ""
        possible <- character()
    }
    else if (length(comps) == 1L)
    {
        ## FIXME (maybe): in certain cases the completion may be
        ## shorter than the token (e.g. when trying to complete on an
        ## impossible name inside a list).  It's debatable what the
        ## behaviour should be in this case, but readline and Emacs
        ## actually delete part of the token (at least currently).  To
        ## achieve this in Rgui one would need to do somewhat more
        ## work than I'm ready to do right now (especially since it's
        ## not clear that this is the right thing to do to begin
        ## with).  So, in this case, I'll just pretend that no
        ## completion was found.

        addition <- substr(comps, nchar(token, type = "chars") + 1L, 100000L)
        possible <- character()
    }
    else if (length(comps) > 1L)
    {
        ## more than one completion.  The right thing to is to extend
        ## the line by the unique part if any, and list the multiple
        ## possibilities otherwise.

        additions <- substr(comps, nchar(token, type = "chars") + 1L, 100000L)
        if (length(table(substr(additions, 1L, 1L))) > 1L)
        {
            ## no unique substring
            addition <- ""
            possible <-
                if (isRepeat) capture.output(cat(format(comps, justify = "left"), fill = TRUE))
                else character()
        }
        else
        {
            ## need to figure out maximal unique substr
            keepUpto <- 1
            while (length(table(substr(additions, 1L, keepUpto))) == 1L)
                keepUpto <- keepUpto + 1L
            addition <- substr(additions[1L], 1L, keepUpto - 1L)
            possible <- character()
        }
    }
    list(addition = addition,
         possible = possible,
         comps = paste(comps, collapse = " "))
}




## usage:

## .addFunctionInfo(foo = c("arg1", "arg2"), bar = c("a", "b"))

.addFunctionInfo <- function(...)
{
    dots <- list(...)
    for (nm in names(dots))
        .FunArgEnv[[nm]] <- dots[[nm]]
}

.initialize.argdb <-
    function()
{
    ## lattice

    lattice.common <-
        c("data", "allow.multiple", "outer", "auto.key", "aspect",
          "panel", "prepanel", "scales", "strip", "groups", "xlab",
          "xlim", "ylab", "ylim", "drop.unused.levels", "...",
          "default.scales", "subscripts", "subset", "formula", "cond",
          "aspect", "as.table", "between", "key", "legend", "page",
          "main", "sub", "par.strip.text", "layout", "skip", "strip",
          "strip.left", "xlab.default", "ylab.default", "xlab",
          "ylab", "panel", "xscale.components", "yscale.components",
          "axis", "index.cond", "perm.cond", "...", "par.settings",
          "plot.args", "lattice.options")

    densityplot <-
        c("plot.points", "ref", "groups", "jitter.amount",
          "bw", "adjust", "kernel", "weights", "window", "width",
          "give.Rkern", "n", "from", "to", "cut", "na.rm")

    panel.xyplot <-
        c("type", "groups", "pch", "col", "col.line",
          "col.symbol", "font", "fontfamily", "fontface", "lty",
          "cex", "fill", "lwd", "horizontal")

    .addFunctionInfo(xyplot.formula = c(lattice.common, panel.xyplot),
                     densityplot.formula = c(lattice.common, densityplot))

    ## grid

    grid.clip <-
        c("x", "y", "width", "height", "just", "hjust", "vjust",
          "default.units", "name", "vp")
    grid.curve <-
        c("x1", "y1", "x2", "y2", "default.units", "curvature",
          "angle", "ncp", "shape", "square", "squareShape", "inflect",
          "arrow", "open", "debug", "name", "gp", "vp")
    grid.polyline <-
        c("x", "y", "id", "id.lengths", "default.units", "arrow",
          "name", "gp", "vp")
    grid.xspline <-
        c("x", "y", "id", "id.lengths", "default.units", "shape",
          "open", "arrow", "repEnds", "name", "gp", "vp")

    .addFunctionInfo(grid.clip = grid.clip,
                     grid.curve = grid.curve,
                     grid.polyline = grid.polyline,
                     grid.xspline = grid.xspline)

    ## par, options

    par <-
        c("xlog", "ylog", "adj", "ann", "ask", "bg", "bty", "cex",
          "cex.axis", "cex.lab", "cex.main", "cex.sub", "cin", "col",
          "col.axis", "col.lab", "col.main", "col.sub", "cra", "crt",
          "csi", "cxy", "din", "err", "family", "fg", "fig", "fin",
          "font", "font.axis", "font.lab", "font.main", "font.sub",
          "gamma", "lab", "las", "lend", "lheight", "ljoin", "lmitre",
          "lty", "lwd", "mai", "mar", "mex", "mfcol", "mfg", "mfrow",
          "mgp", "mkh", "new", "oma", "omd", "omi", "pch", "pin",
          "plt", "ps", "pty", "smo", "srt", "tck", "tcl", "usr",
          "xaxp", "xaxs", "xaxt", "xpd", "yaxp", "yaxs", "yaxt")

    options <- c("add.smooth", "browser", "check.bounds", "continue",
	"contrasts", "defaultPackages", "demo.ask", "device",
	"digits", "dvipscmd", "echo", "editor", "encoding",
	"example.ask", "expressions", "help.search.types",
	"help.try.all.packages", "htmlhelp", "HTTPUserAgent",
	"internet.info", "keep.source", "keep.source.pkgs",
	"locatorBell", "mailer", "max.print", "menu.graphics",
	"na.action", "OutDec", "pager", "papersize",
	"par.ask.default", "pdfviewer", "pkgType", "printcmd",
	"prompt", "repos", "scipen", "show.coef.Pvalues",
	"show.error.messages", "show.signif.stars", "str",
	"stringsAsFactors", "timeout", "ts.eps", "ts.S.compat",
	"unzip", "verbose", "warn", "warning.length", "width")

    .addFunctionInfo(par = par, options = options)

    ## read.csv etc (... passed to read.table)

}



.CompletionEnv <- new.env(hash = FALSE)

## needed to save some overhead in .win32consoleCompletion
assign("linebuffer", "", env = .CompletionEnv)
assign("end", 1, env = .CompletionEnv)

assign("settings",
       list(ops = TRUE, ns = TRUE,
            args = TRUE, func = FALSE,
            ipck = FALSE, S3 = TRUE, data = TRUE,
            help = TRUE, argdb = TRUE,
            files = .Platform$OS.type == "windows"),
       env = .CompletionEnv)


assign("options",
       list(package.suffix = "::",
            funarg.suffix = "=",
            function.suffix = "("),
       env = .CompletionEnv)

.FunArgEnv <- new.env(hash = TRUE, parent = emptyenv())

.initialize.argdb() ## see argdb.R

