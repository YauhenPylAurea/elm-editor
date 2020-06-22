module Config exposing (..)

import Types exposing (AppMode(..), FileLocation(..))


appMode =
    Desktop


tickInterval =
    10000


messageLifeTime =
    5


fileLocation =
    ServerFiles


localServerUrl =
    "http://localhost:4000/api"


remoteServerUrl =
    "http://localhost:4000/api"



--- "http://161.35.125.40:80/api"


token =
    "abracadabra"
