{-# LANGUAGE ExistentialQuantification, TypeSynonymInstances, FlexibleInstances #-}
-- |This module provides visual borders to be placed between and
-- around widgets.  Border widgets in this module use the active
-- 'Skin' in the 'RenderContext'.
module Graphics.Vty.Widgets.Borders
    ( HasBorderAttr(..)
    , Bordered
    , HBorder
    , VBorder
    -- * Border Widget Constructors
    , vBorder
    , hBorder
    , bordered
    -- * Setting Attributes and Labels
    , withBorderAttribute
    , withHBorderLabel
    , withBorderedLabel
    , setHBorderLabel
    , setBorderedLabel
    )
where

import Graphics.Vty
import Graphics.Vty.Widgets.Core
import Graphics.Vty.Widgets.Box
import Graphics.Vty.Widgets.Text
import Graphics.Vty.Widgets.Util
import Graphics.Vty.Widgets.Skins

-- |The class of types with a border attribute, which differs from the
-- |normal and focused attributes.
class HasBorderAttr a where
    setBorderAttribute :: a -> Attr -> IO ()

data HBorder = HBorder Attr String
               deriving (Show)

instance HasBorderAttr (Widget HBorder) where
    setBorderAttribute t a =
        updateWidgetState t $ \(HBorder a' s) -> HBorder (mergeAttr a a') s

withBorderAttribute :: (HasBorderAttr a) => Attr -> a -> IO a
withBorderAttribute att w = setBorderAttribute w att >> return w

withHBorderLabel :: String -> Widget HBorder -> IO (Widget HBorder)
withHBorderLabel label w = setHBorderLabel w label >> return w

setHBorderLabel :: Widget HBorder -> String -> IO ()
setHBorderLabel w label =
    updateWidgetState w $ \(HBorder a _) -> HBorder a label

withBorderedLabel :: String -> Widget (Bordered a) -> IO (Widget (Bordered a))
withBorderedLabel label w = setBorderedLabel w label >> return w

setBorderedLabel :: Widget (Bordered a) -> String -> IO ()
setBorderedLabel w label =
    updateWidgetState w $ \(Bordered a ch _) -> Bordered a ch label

-- |Create a single-row horizontal border using the specified
-- attribute and character.
hBorder :: IO (Widget HBorder)
hBorder = do
  wRef <- newWidget $ \w ->
      w { state = HBorder def_attr ""
        , growHorizontal_ = const $ return True
        , render_ = renderHBorder
        }
  return wRef

renderHBorder :: Widget HBorder -> DisplayRegion -> RenderContext -> IO Image
renderHBorder _ (DisplayRegion 0 _) _ = return empty_image
renderHBorder _ (DisplayRegion _ 0) _ = return empty_image
renderHBorder this s ctx = do
  HBorder attr str <- getState this
  let attr' = mergeAttrs [ overrideAttr ctx
                         , attr
                         , normalAttr ctx
                         ]
      noTitle = char_fill attr' (skinHorizontal $ skin ctx) (region_width s) 1
  case null str of
    True -> return noTitle
    False -> do
      let title = " " ++ str ++ " "
      case (toEnum $ length title) > region_width s of
        True -> return noTitle
        False -> do
                  let remaining = region_width s - (toEnum $ length title)
                      side1 = remaining `div` 2
                      side2 = if remaining `mod` 2 == 0 then side1 else side1 + 1
                  return $ horiz_cat [ char_fill attr' (skinHorizontal $ skin ctx) side1 1
                                     , string attr' title
                                     , char_fill attr' (skinHorizontal $ skin ctx) side2 1
                                     ]

data VBorder = VBorder Attr
               deriving (Show)

instance HasBorderAttr (Widget VBorder) where
    setBorderAttribute t a =
        updateWidgetState t $ \(VBorder a') -> VBorder (mergeAttr a a')

-- |Create a single-column vertical border using the specified
-- attribute and character.
vBorder :: IO (Widget VBorder)
vBorder = do
  wRef <- newWidget $ \w ->
      w { state = VBorder def_attr
        , growVertical_ = const $ return True
        , render_ = \this s ctx -> do
                   VBorder attr <- getState this
                   let attr' = mergeAttrs [ overrideAttr ctx
                                          , attr
                                          , normalAttr ctx
                                          ]
                   return $ char_fill attr' (skinVertical $ skin ctx) 1 (region_height s)
        }
  return wRef

data Bordered a = (Show a) => Bordered Attr (Widget a) String

instance Show (Bordered a) where
    show (Bordered attr _ l) = concat [ "Bordered { attr = "
                                      , show attr
                                      , ", label = "
                                      , show l
                                      , ", ... }"
                                      ]

instance HasBorderAttr (Widget (Bordered a)) where
    setBorderAttribute t a =
        updateWidgetState t $ \(Bordered a' ch s) -> Bordered (mergeAttr a a') ch s

-- |Wrap a widget in a bordering box.
bordered :: (Show a) => Widget a -> IO (Widget (Bordered a))
bordered child = do
  wRef <- newWidget $ \w ->
      w { state = Bordered def_attr child ""

        , growVertical_ = const $ growVertical child
        , growHorizontal_ = const $ growHorizontal child

        , keyEventHandler =
            \this key mods -> do
              Bordered _ ch _ <- getState this
              handleKeyEvent ch key mods

        , render_ =
            \this s ctx -> do
              st <- getState this
              drawBordered st s ctx

        , setCurrentPosition_ =
            \this pos -> do
              Bordered _ ch _ <- getState this
              let chPos = pos `plusWidth` 1 `plusHeight` 1
              setCurrentPosition ch chPos
        }
  wRef `relayFocusEvents` child
  wRef `relayKeyEvents` child
  return wRef

drawBordered :: (Show a) =>
                Bordered a -> DisplayRegion -> RenderContext -> IO Image
drawBordered this s ctx = do
  let Bordered attr child label = this
      attr' = mergeAttrs [ overrideAttr ctx
                         , attr
                         , normalAttr ctx
                         ]
      sk = skin ctx

  -- Render the contained widget with enough room to draw borders.
  -- Then, use the size of the rendered widget to constrain the space
  -- used by the (expanding) borders.
  let constrained = DisplayRegion (region_width s - 2) (region_height s - 2)

  childImage <- render child constrained ctx

  let adjusted = DisplayRegion (image_width childImage + 2)
                 (image_height childImage)

  tlCorner <- plainText [skinCornerTL sk] >>= withNormalAttribute attr'
  trCorner <- plainText [skinCornerTR sk] >>= withNormalAttribute attr'
  blCorner <- plainText [skinCornerBL sk] >>= withNormalAttribute attr'
  brCorner <- plainText [skinCornerBR sk] >>= withNormalAttribute attr'

  hb <- hBorder >>= withHBorderLabel label
  setBorderAttribute hb attr'

  topWidget <- hBox tlCorner =<< hBox hb trCorner
  top <- render topWidget adjusted ctx

  hb2 <- hBorder
  bottomWidget <- hBox blCorner =<< hBox hb2 brCorner
  bottom <- render bottomWidget adjusted ctx

  vb <- vBorder
  setBorderAttribute vb attr'

  leftRight <- render vb adjusted ctx

  let middle = horiz_cat [leftRight, childImage, leftRight]

  return $ vert_cat [top, middle, bottom]
